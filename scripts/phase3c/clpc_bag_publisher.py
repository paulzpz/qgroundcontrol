#!/usr/bin/env python3
"""
clpc_bag_publisher.py — проигрыватель ROS2 bag -> CLPC TCP stream.

Читает ROS2 bag (sqlite3 .db3 или .mcap) БЕЗ установки ROS (библиотека rosbags).
Берёт облако точек (sensor_msgs/PointCloud2 ИЛИ livox_ros_driver2/CustomMsg)
+ Odometry (nav_msgs/Odometry) для pose, делает voxel downsample и стримит
кадры по протоколу CLPC v1 (см. CLPC_PROTOCOL.md) на TCP-порт.

Совместим с приёмником CustomPointCloudReceiver из Innovatech Control (TASK-QGC.3/.4).

Примеры:
  # авто-детект топиков:
  python3 clpc_bag_publisher.py --bag ~/bags/flight31

  # явные топики, ускоренное воспроизведение, более крупный воксель:
  python3 clpc_bag_publisher.py --bag ~/bags/flight31 \
      --cloud-topic /livox/lidar --odom-topic /Odometry \
      --voxel 0.30 --rate 2.0 --speed 1.0 --port 7777 --loop

Зависимости: pip install rosbags numpy
"""

import argparse
import socket
import struct
import sys
import threading
import time
from pathlib import Path

import numpy as np

from rosbags.highlevel import AnyReader
from rosbags.typesys import Stores, get_typestore, get_types_from_msg

# ---------------------------------------------------------------------------
# Livox CustomMsg — регистрируем тип (в sqlite3-bag'ах определения типов нет)
# ---------------------------------------------------------------------------
LIVOX_CUSTOM_POINT = """
uint32 offset_time
float32 x
float32 y
float32 z
uint8 reflectivity
uint8 tag
uint8 line
"""

LIVOX_CUSTOM_MSG = """
std_msgs/Header header
uint64 timebase
uint32 point_num
uint8 lidar_id
uint8[3] rsvd
livox_ros_driver2/CustomPoint[] points
"""


def make_typestore(ros_version=2):
    """Create typestore with Livox custom types for ROS1 or ROS2."""
    if ros_version == 1:
        ts = get_typestore(Stores.ROS1_NOETIC)
        # ROS1 Livox driver (rosbags uses /msg/ even for ROS1)
        custom = {}
        custom.update(get_types_from_msg(LIVOX_CUSTOM_POINT,
                                         'livox_ros_driver/msg/CustomPoint'))
        livox_msg_ros1 = LIVOX_CUSTOM_MSG.replace('livox_ros_driver2', 'livox_ros_driver')
        custom.update(get_types_from_msg(livox_msg_ros1,
                                         'livox_ros_driver/msg/CustomMsg'))
        ts.register(custom)
    else:
        ts = get_typestore(Stores.ROS2_HUMBLE)
        # ROS2 Livox driver
        custom = {}
        custom.update(get_types_from_msg(LIVOX_CUSTOM_POINT,
                                         'livox_ros_driver2/msg/CustomPoint'))
        custom.update(get_types_from_msg(LIVOX_CUSTOM_MSG,
                                         'livox_ros_driver2/msg/CustomMsg'))
        ts.register(custom)
    return ts


# ---------------------------------------------------------------------------
# CLPC v1 (ровно как в CLPC_PROTOCOL.md / TASK_QGC3_REPORT)
# Header 58 байт LE: magic 4s, version u16, frame u32, ts u64, count u32,
#   flags u32, pose 3*f32, quat(w,x,y,z) 4*f32, voxel f32
# Point 13 байт: x,y,z f32 + intensity u8
# ---------------------------------------------------------------------------
CLPC_HDR = struct.Struct('<4sHIQII3f4ff')
assert CLPC_HDR.size == 58, CLPC_HDR.size
FLAG_HAS_INTENSITY = 1 << 0
FLAG_SOURCE_REPLAY = 1 << 2


def pack_frame(frame_id, t_us, pts_xyz, intens, pose_xyz, pose_q_wxyz, voxel):
    n = len(pts_xyz)
    flags = FLAG_HAS_INTENSITY | FLAG_SOURCE_REPLAY
    hdr = CLPC_HDR.pack(b'CLPC', 1, frame_id, t_us, n, flags,
                        float(pose_xyz[0]), float(pose_xyz[1]), float(pose_xyz[2]),
                        float(pose_q_wxyz[0]), float(pose_q_wxyz[1]),
                        float(pose_q_wxyz[2]), float(pose_q_wxyz[3]),
                        float(voxel))
    body = bytearray()
    xyz = np.asarray(pts_xyz, dtype='<f4')
    ii = np.asarray(intens, dtype=np.uint8)
    # interleave: 12 байт xyz + 1 байт intensity на точку
    rec = np.zeros(n, dtype=[('xyz', '<f4', 3), ('i', 'u1')])
    rec['xyz'] = xyz
    rec['i'] = ii
    body = rec.tobytes()
    return hdr + body


# ---------------------------------------------------------------------------
# Парсинг облаков
# ---------------------------------------------------------------------------
def parse_pointcloud2(msg):
    """Достаём x,y,z (+intensity если есть) из PointCloud2 любым layout'ом."""
    off = {f.name: (f.offset, f.datatype) for f in msg.fields}
    if not all(k in off for k in ('x', 'y', 'z')):
        return None, None
    step = msg.point_step
    n = msg.width * msg.height
    buf = np.frombuffer(msg.data, dtype=np.uint8).reshape(n, step)

    def f32_at(o):
        return buf[:, o:o + 4].copy().view('<f4').reshape(n)

    x, y, z = f32_at(off['x'][0]), f32_at(off['y'][0]), f32_at(off['z'][0])
    if 'intensity' in off:
        o, dt = off['intensity']
        if dt == 7:        # FLOAT32
            it = f32_at(o)
            it = np.clip(it, 0, 255).astype(np.uint8)
        elif dt in (2, 4): # UINT8 / UINT16
            it = buf[:, o].copy() if dt == 2 else \
                 (buf[:, o:o + 2].copy().view('<u2').reshape(n) >> 8).astype(np.uint8)
        else:
            it = np.full(n, 128, np.uint8)
    else:
        it = np.full(n, 128, np.uint8)
    pts = np.stack([x, y, z], axis=1)
    ok = np.isfinite(pts).all(axis=1)
    return pts[ok], it[ok]


def parse_livox_custom(msg):
    pts = np.array([[p.x, p.y, p.z] for p in msg.points], dtype='<f4')
    it = np.array([p.reflectivity for p in msg.points], dtype=np.uint8)
    if len(pts) == 0:
        return pts, it
    ok = np.isfinite(pts).all(axis=1)
    return pts[ok], it[ok]


def voxel_downsample(pts, intens, voxel):
    if voxel <= 0 or len(pts) == 0:
        return pts, intens
    keys = np.floor(pts / voxel).astype(np.int64)
    # уникальный воксель -> первая точка (быстро и достаточно для preview)
    _, idx = np.unique(keys, axis=0, return_index=True)
    idx.sort()
    return pts[idx], intens[idx]


# ---------------------------------------------------------------------------
# TCP сервер (мультиклиент: пилот + ноут — как в production)
# ---------------------------------------------------------------------------
class Server:
    def __init__(self, host, port):
        self.clients = []
        self.lock = threading.Lock()
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind((host, port))
        s.listen(4)
        self.sock = s
        threading.Thread(target=self._accept, daemon=True).start()
        print(f'CLPC bag publisher on {host}:{port}')

    def _accept(self):
        while True:
            c, addr = self.sock.accept()
            c.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
            print(f'client connected: {addr}')
            with self.lock:
                self.clients.append(c)

    def send(self, data):
        with self.lock:
            dead = []
            for c in self.clients:
                try:
                    c.sendall(data)
                except OSError:
                    dead.append(c)
            for c in dead:
                print('client disconnected')
                self.clients.remove(c)
                c.close()

    @property
    def nclients(self):
        with self.lock:
            return len(self.clients)


# ---------------------------------------------------------------------------
def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--bag', required=True, help='путь к ROS2 bag (директория)')
    ap.add_argument('--cloud-topic', default=None,
                    help='топик облака (автодетект если не задан)')
    ap.add_argument('--odom-topic', default=None,
                    help='топик Odometry для pose (автодетект)')
    ap.add_argument('--host', default='0.0.0.0')
    ap.add_argument('--port', type=int, default=7777)
    ap.add_argument('--voxel', type=float, default=0.30, help='воксель, м')
    ap.add_argument('--rate', type=float, default=0.0,
                    help='форсировать частоту кадров (0 = по timestamp bag)')
    ap.add_argument('--speed', type=float, default=1.0, help='множитель скорости')
    ap.add_argument('--range-max', type=float, default=30.0,
                    help='обрезка дальности от сенсора, м')
    ap.add_argument('--loop', action='store_true', help='зациклить воспроизведение')
    args = ap.parse_args()

    bagpath = Path(args.bag).expanduser()

    # Detect ROS version from bag extension
    is_ros1 = str(bagpath).endswith('.bag')
    ts = make_typestore(ros_version=1 if is_ros1 else 2)
    srv = Server(args.host, args.port)

    # Support both ROS1 and ROS2 message types
    CLOUD_TYPES = (
        'sensor_msgs/msg/PointCloud2',
        'sensor_msgs/PointCloud2',
        'livox_ros_driver2/msg/CustomMsg',
        'livox_ros_driver/msg/CustomMsg',
        'livox_ros_driver/CustomMsg',
    )
    ODOM_TYPES = ('nav_msgs/msg/Odometry', 'nav_msgs/Odometry')

    while True:
        with AnyReader([bagpath], default_typestore=ts) as reader:
            # --- выбор топиков
            conns = reader.connections
            if args.cloud_topic:
                cloud_conns = [c for c in conns if c.topic == args.cloud_topic]
            else:
                cloud_conns = [c for c in conns if c.msgtype in CLOUD_TYPES]
            if args.odom_topic:
                odom_conns = [c for c in conns if c.topic == args.odom_topic]
            else:
                odom_conns = [c for c in conns if c.msgtype in ODOM_TYPES]

            if not cloud_conns:
                print('Облачный топик не найден. В bag есть:')
                for c in conns:
                    print(f'  {c.topic}  [{c.msgtype}]')
                sys.exit(1)
            cloud_conn = cloud_conns[0]
            odom_conn = odom_conns[0] if odom_conns else None
            print(f'cloud: {cloud_conn.topic} [{cloud_conn.msgtype}]')
            print(f'odom : {odom_conn.topic if odom_conn else "— (pose=0)"}')

            pose_xyz = np.zeros(3)
            pose_q = np.array([1.0, 0.0, 0.0, 0.0])  # w,x,y,z
            frame_id = 0
            t_prev_bag = None
            t_prev_wall = None
            sel = [cloud_conn] + ([odom_conn] if odom_conn else [])

            for conn, t_ns, raw in reader.messages(connections=sel):
                if conn is odom_conn:
                    m = reader.deserialize(raw, conn.msgtype)
                    p = m.pose.pose.position
                    q = m.pose.pose.orientation
                    pose_xyz = np.array([p.x, p.y, p.z])
                    pose_q = np.array([q.w, q.x, q.y, q.z])
                    continue

                m = reader.deserialize(raw, conn.msgtype)
                if 'PointCloud2' in conn.msgtype:
                    pts, it = parse_pointcloud2(m)
                else:
                    pts, it = parse_livox_custom(m)
                if pts is None or len(pts) == 0:
                    continue

                # обрезка дальности (точки в фрейме сенсора/карты — для preview ок)
                d = np.linalg.norm(pts, axis=1)
                keep = d < args.range_max
                pts, it = pts[keep], it[keep]
                pts, it = voxel_downsample(pts, it, args.voxel)

                # --- пейсинг
                if args.rate > 0:
                    time.sleep(1.0 / args.rate)
                else:
                    if t_prev_bag is not None:
                        dt = (t_ns - t_prev_bag) / 1e9 / args.speed
                        lag = time.monotonic() - t_prev_wall
                        if dt - lag > 0:
                            time.sleep(dt - lag)
                    t_prev_bag, t_prev_wall = t_ns, time.monotonic()

                frame_id += 1
                data = pack_frame(frame_id, t_ns // 1000, pts, it,
                                  pose_xyz, pose_q, args.voxel)
                srv.send(data)
                if frame_id % 10 == 0:
                    print(f'frame {frame_id}: {len(pts)} pts '
                          f'(voxel {args.voxel}m), clients: {srv.nclients}')

        if not args.loop:
            break
        print('--- loop ---')

    print('bag finished.')


if __name__ == '__main__':
    main()
