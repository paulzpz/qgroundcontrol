# TASK-QGC.5 Status - 2026-06-05

## Final State Today

Working demo confirmed.

- QGC executable: `/home/paulzp/qgroundcontrol/build/Debug/InnovatechControl`.
- Launch script: `/home/paulzp/qgroundcontrol/scripts/phase3c/run_qgc5_bag_video.sh`.
- Stop script command: `/home/paulzp/qgroundcontrol/scripts/phase3c/run_qgc5_bag_video.sh --stop`.
- Point cloud source: ROS2 bag `/home/paulzp/Downloads/rosbag2_2024_04_16-14_17_01/rosbag2_2024_04_16-14_17_01`.
- Video source: `/home/paulzp/Downloads/videoplayback.mp4` streamed as RTP/H.264 into the standard QGC video window.

## Implemented Metric Sizes

- Drone marker: `0.7 m` body length.
- Coordinate axes: `0.1 m` thickness.
- Point diameter: `0.02 m` setting, converted to shader pixel size at runtime.
- Axis length: `2.0 m`.
- Ground grid: `100 m x 100 m`.

## Working Launch

```bash
/home/paulzp/qgroundcontrol/scripts/phase3c/run_qgc5_bag_video.sh
```

This starts:
- CLPC bag publisher on TCP `127.0.0.1:7777`.
- RTP/H.264 video stream to UDP `127.0.0.1:5600`.
- QGC/InnovatechControl.

## Logs

```text
/tmp/qgc5-innovatechcontrol.log
/tmp/qgc5-clpc-publisher.log
/tmp/qgc5-video-rtp.log
```

## Known Limitation

The supplied ROS2 bag has lidar but no odometry topic, so drone pose remains zero/origin. Point cloud reception/rendering and video integration are working.
