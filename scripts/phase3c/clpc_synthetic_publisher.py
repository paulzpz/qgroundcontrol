#!/usr/bin/env python3
"""
CLPC Synthetic Publisher - Reference Implementation

Generates synthetic point cloud data and streams it via TCP using the CLPC protocol.
Used for development and testing of the QGC point cloud receiver without drone hardware.

Usage:
    python3 clpc_synthetic_publisher.py --host 127.0.0.1 --port 7777 --hz 2

Protocol: CLPC v1 (see custom/docs/CLPC_PROTOCOL.md)
"""

import argparse
import socket
import struct
import time
import math
import random
import threading
from typing import List, Tuple, Optional


# CLPC Protocol Constants
CLPC_MAGIC = b'CLPC'
CLPC_VERSION = 1
CLPC_HEADER_FORMAT = '<4sHIQII3f4ff'  # magic, version, frame_id, timestamp_us, point_count, flags, pose_xyz, pose_q, voxel_size
CLPC_HEADER_SIZE = struct.calcsize(CLPC_HEADER_FORMAT)
CLPC_POINT_FORMAT = '<3fB'  # x, y, z, intensity (B = unsigned byte)
CLPC_POINT_SIZE = struct.calcsize(CLPC_POINT_FORMAT)

# Flags
FLAG_HAS_INTENSITY = 0x01
FLAG_SOURCE_SIM = 0x02


class SyntheticPointCloudGenerator:
    """Generates synthetic point cloud data simulating a wall in front of the drone."""

    def __init__(self,
                 wall_distance: float = 0.25,
                 wall_width: float = 2.0,
                 wall_height: float = 2.0,
                 voxel_size: float = 0.03,
                 noise_std: float = 0.005):
        """
        Args:
            wall_distance: Distance to wall along +X axis (meters)
            wall_width: Wall width along Y axis (meters)
            wall_height: Wall height along Z axis (meters)
            voxel_size: Voxel grid size for point spacing (meters)
            noise_std: Gaussian noise standard deviation (meters)
        """
        self.wall_distance = wall_distance
        self.wall_width = wall_width
        self.wall_height = wall_height
        self.voxel_size = voxel_size
        self.noise_std = noise_std

        # Pre-generate base wall points
        self._generate_base_wall()

    def _generate_base_wall(self):
        """Generate base wall point grid."""
        self.base_points = []

        # Number of points in each direction
        ny = int(self.wall_width / self.voxel_size)
        nz = int(self.wall_height / self.voxel_size)

        for iy in range(ny):
            for iz in range(nz):
                y = -self.wall_width / 2 + iy * self.voxel_size
                z = iz * self.voxel_size
                self.base_points.append((y, z))

        print(f"Generated {len(self.base_points)} base wall points")

    def generate_frame(self, t: float) -> Tuple[List[Tuple[float, float, float, int]],
                                                  Tuple[float, float, float],
                                                  Tuple[float, float, float, float]]:
        """
        Generate a single frame of point cloud data.

        Args:
            t: Time in seconds (for animation)

        Returns:
            points: List of (x, y, z, intensity) tuples
            position: (x, y, z) drone position
            orientation: (qw, qx, qy, qz) drone orientation
        """
        # Simulate slowly moving drone
        drone_x = 0.05 * math.sin(t * 0.3)
        drone_y = 0.02 * math.sin(t * 0.2)
        drone_z = 1.5 + 0.1 * math.sin(t * 0.1)

        # Simulate slight rotation
        yaw = 0.1 * math.sin(t * 0.15)
        # Convert yaw to quaternion (rotation around Z)
        qw = math.cos(yaw / 2)
        qx = 0.0
        qy = 0.0
        qz = math.sin(yaw / 2)

        # Generate points with noise
        points = []
        for y_base, z_base in self.base_points:
            # Add noise to position
            x = self.wall_distance + random.gauss(0, self.noise_std)
            y = y_base + random.gauss(0, self.noise_std)
            z = z_base + random.gauss(0, self.noise_std)

            # Simulate intensity based on distance and angle
            # Higher intensity in center, lower at edges
            intensity_factor = 1.0 - 0.3 * (abs(y_base) / (self.wall_width / 2))
            intensity = int(min(255, max(0, 200 * intensity_factor + random.randint(-20, 20))))

            points.append((x, y, z, intensity))

        return points, (drone_x, drone_y, drone_z), (qw, qx, qy, qz)


class CLPCPublisher:
    """TCP server that streams CLPC point cloud frames to connected clients."""

    def __init__(self, host: str, port: int, hz: float, voxel_size: float = 0.03):
        self.host = host
        self.port = port
        self.period = 1.0 / hz
        self.voxel_size = voxel_size
        self.frame_id = 0
        self.running = False
        self.clients: List[socket.socket] = []
        self.clients_lock = threading.Lock()

        self.generator = SyntheticPointCloudGenerator(voxel_size=voxel_size)

        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

    def _pack_frame(self, points: List[Tuple[float, float, float, int]],
                    position: Tuple[float, float, float],
                    orientation: Tuple[float, float, float, float]) -> bytes:
        """Pack point cloud data into CLPC binary frame."""

        timestamp_us = int(time.monotonic() * 1_000_000)
        point_count = len(points)
        flags = FLAG_HAS_INTENSITY | FLAG_SOURCE_SIM

        # Pack header
        header = struct.pack(
            CLPC_HEADER_FORMAT,
            CLPC_MAGIC,
            CLPC_VERSION,
            self.frame_id,
            timestamp_us,
            point_count,
            flags,
            position[0], position[1], position[2],
            orientation[0], orientation[1], orientation[2], orientation[3],
            self.voxel_size
        )

        # Pack points
        point_data = b''.join(
            struct.pack(CLPC_POINT_FORMAT, x, y, z, intensity)
            for x, y, z, intensity in points
        )

        return header + point_data

    def _accept_clients(self):
        """Accept incoming client connections."""
        while self.running:
            try:
                self.server_socket.settimeout(1.0)
                client_socket, addr = self.server_socket.accept()
                client_socket.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)

                with self.clients_lock:
                    self.clients.append(client_socket)

                print(f"Client connected from {addr}, total clients: {len(self.clients)}")

            except socket.timeout:
                continue
            except OSError:
                break

    def _stream_frames(self):
        """Generate and stream frames to all connected clients."""
        start_time = time.monotonic()

        while self.running:
            frame_start = time.monotonic()
            t = frame_start - start_time

            # Generate frame
            points, position, orientation = self.generator.generate_frame(t)
            frame_data = self._pack_frame(points, position, orientation)

            # Send to all clients
            disconnected = []
            with self.clients_lock:
                for client in self.clients:
                    try:
                        client.sendall(frame_data)
                    except (BrokenPipeError, ConnectionResetError, OSError):
                        disconnected.append(client)

                for client in disconnected:
                    self.clients.remove(client)
                    try:
                        client.close()
                    except:
                        pass
                    print(f"Client disconnected, remaining clients: {len(self.clients)}")

            self.frame_id += 1

            # Print status periodically
            if self.frame_id % 10 == 0:
                print(f"Frame {self.frame_id}: {len(points)} points, "
                      f"pose ({position[0]:.2f}, {position[1]:.2f}, {position[2]:.2f}), "
                      f"clients: {len(self.clients)}")

            # Sleep to maintain frame rate
            elapsed = time.monotonic() - frame_start
            sleep_time = self.period - elapsed
            if sleep_time > 0:
                time.sleep(sleep_time)

    def start(self):
        """Start the CLPC publisher server."""
        self.server_socket.bind((self.host, self.port))
        self.server_socket.listen(5)
        self.running = True

        print(f"CLPC Publisher started on {self.host}:{self.port}")
        print(f"Frame rate: {1.0/self.period:.1f} Hz, Voxel size: {self.voxel_size:.3f} m")
        print("Waiting for clients...")

        # Start accept thread
        accept_thread = threading.Thread(target=self._accept_clients, daemon=True)
        accept_thread.start()

        # Stream frames in main thread
        try:
            self._stream_frames()
        except KeyboardInterrupt:
            print("\nShutting down...")
        finally:
            self.stop()

    def stop(self):
        """Stop the publisher and clean up."""
        self.running = False

        with self.clients_lock:
            for client in self.clients:
                try:
                    client.close()
                except:
                    pass
            self.clients.clear()

        try:
            self.server_socket.close()
        except:
            pass

        print("CLPC Publisher stopped")


def main():
    parser = argparse.ArgumentParser(
        description='CLPC Synthetic Publisher - streams synthetic point cloud data via TCP'
    )
    parser.add_argument('--host', type=str, default='127.0.0.1',
                        help='Host address to bind to (default: 127.0.0.1)')
    parser.add_argument('--port', type=int, default=7777,
                        help='TCP port to listen on (default: 7777)')
    parser.add_argument('--hz', type=float, default=2.0,
                        help='Frame rate in Hz (default: 2.0)')
    parser.add_argument('--voxel-size', type=float, default=0.03,
                        help='Voxel size in meters (default: 0.03)')

    args = parser.parse_args()

    publisher = CLPCPublisher(
        host=args.host,
        port=args.port,
        hz=args.hz,
        voxel_size=args.voxel_size
    )

    publisher.start()


if __name__ == '__main__':
    main()
