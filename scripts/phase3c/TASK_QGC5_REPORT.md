# TASK-QGC.5 Final Report - 2026-06-05

## Status

Done for the day. The working demo is running in QGC and was visually confirmed by the user.

Current behavior:
- Point cloud is received from the ROS2 bag and rendered in the custom QGC point cloud panel.
- Coordinate axes are visible and scaled in meters.
- Drone marker is visible and scaled in meters.
- Local MP4 video is shown through the existing QGC video window/PIP path, not through a separate QML overlay.
- The QGC window, CLPC bag publisher, and RTP video streamer are currently running.

## Metric Requirements

Implemented metric defaults:
- Drone body length: `0.7 m`.
- Coordinate axis thickness: `0.1 m`.
- Point diameter setting: `0.02 m`.
- Coordinate axis length: `2.0 m`.
- Ground plane: `100 m x 100 m`.

Qt Quick 3D point primitives still render via shader `POINT_SIZE`, which is a pixel value. The implementation keeps the external setting in meters and converts `0.02 m` to pixel size from camera distance, with a 1 px minimum visibility floor.

## Data Sources Used

ROS2 bag:

```text
/home/paulzp/Downloads/rosbag2_2024_04_16-14_17_01/rosbag2_2024_04_16-14_17_01
```

Video file:

```text
/home/paulzp/Downloads/videoplayback.mp4
```

Detected bag topics:
- Cloud: `/livox/lidar [sensor_msgs/msg/PointCloud2]`.
- Odometry: none detected, so drone pose remains at origin/zero pose.

## Launch And Stop

Primary launch script:

```bash
/home/paulzp/qgroundcontrol/scripts/phase3c/run_qgc5_bag_video.sh
```

Stop everything started by the launcher:

```bash
/home/paulzp/qgroundcontrol/scripts/phase3c/run_qgc5_bag_video.sh --stop
```

Logs:

```text
/tmp/qgc5-innovatechcontrol.log
/tmp/qgc5-clpc-publisher.log
/tmp/qgc5-video-rtp.log
```

The launcher starts:
- `clpc_bag_publisher.py` with `--voxel 0.30 --rate 5 --range-max 30 --loop`.
- `ffmpeg` streaming `/home/paulzp/Downloads/videoplayback.mp4` as RTP/H.264 to `127.0.0.1:5600`.
- `/home/paulzp/qgroundcontrol/build/Debug/InnovatechControl`.

## Video Integration

The first attempt used a small custom `QtMultimedia` overlay in `FlyViewCustomLayer.qml`. That was removed because the requirement is to use the QGC video window that already exists.

Final video path:
- QGC `VideoManager` uses the built-in `FlyViewVideo -> FlightDisplayViewVideo -> QGCVideoBackground` pipeline.
- QGC settings are configured for `UDP h.264 Video Stream`.
- `udpUrl` must be `0.0.0.0:5600` in QGC settings, without an `udp://` prefix. QGC adds that prefix internally.
- `ffmpeg` sends baseline H.264/yuv420p RTP packets to avoid the green-stripe artifact seen with the direct overlay path.

Relevant QGC settings file:

```text
/home/paulzp/.config/Innovatech/InnovatechControl.ini
```

Current video settings written by the launcher:

```ini
[Video]
videoSource=UDP h.264 Video Stream
udpUrl=0.0.0.0:5600
streamEnabled=true
aspectRatio=1.777777
videoFit=1
gridLines=false
lowLatencyMode=true

[QGCQml]
MainFlyWindowIsMap=false
IsPIPVisible=true
```

## Point Cloud Implementation

Main files:
- `custom/src/PointCloudGeometry.h`
- `custom/src/PointCloudGeometry.cc`
- `custom/src/PointCloudView.qml`
- `custom/src/shaders/pointcloud.vert`
- `custom/src/shaders/pointcloud.frag`

Important implementation details:
- `PointCloudGeometry` exposes `pointDiameter` as a C++/QML property in meters.
- Geometry still uses `QQuick3DGeometry::PrimitiveType::Points`.
- QML computes `pointSizePixels` from `pointDiameter`, camera distance, view height, and camera FOV.
- Shader receives `pointSize` and writes `POINT_SIZE = pointSize`.
- Built-in Quick3D primitives are scaled with `meters / 100.0`, matching their built-in 100-unit primitive size.

## Validation

Build command passed:

```bash
cmake --build /home/paulzp/qgroundcontrol/build --target InnovatechControl -j 4
```

Runtime validation:
- QGC connected to the CLPC TCP publisher.
- Publisher log showed one client connected.
- Frames streamed at 5 FPS with roughly 3k-9k downsampled points per frame depending on bag position.
- User confirmed the final state works: point cloud, axes, drone marker, and QGC video window.

## Current Running Processes At Report Time

```text
330800 clpc_bag_publisher.py --bag ... --voxel 0.30 --rate 5 --range-max 30 --loop
330801 ffmpeg ... videoplayback.mp4 ... RTP/H.264 udp://127.0.0.1:5600
330867 InnovatechControl
```

These PIDs are only a snapshot. Use the stop command above instead of relying on PIDs.

## Notes For Next Session

- If the video window says waiting for video, check that `ffmpeg` is running and that QGC `udpUrl` is exactly `0.0.0.0:5600`.
- If point cloud is disconnected, check `/tmp/qgc5-clpc-publisher.log` and confirm the publisher has `clients: 1`.
- This bag has no odometry topic, so moving-drone-over-static-map behavior cannot be validated from this data alone.
- The current point diameter is metric in the UI, but rendered through `POINT_SIZE`; true world-space point spheres would require instancing or mesh expansion and would be heavier.
