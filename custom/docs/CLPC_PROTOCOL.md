# CLPC Protocol v1 - Colibri LiDAR Point Cloud

**Version:** 1.0
**Date:** 2026-06-05
**Status:** MVP / Development

## Overview

CLPC (Colibri LiDAR Point Cloud) is a lightweight binary protocol for streaming
voxel-downsampled point cloud data from the drone (Radxa/OrangePi) to ground
control stations (QGC fork "Innovatech Control").

The protocol is designed for real-time transmission of LiDAR point cloud data
with drone pose information, suitable for inspection and measurement applications.

## Transport

- **Protocol:** TCP
- **Default Port:** 7777
- **Byte Order:** Little-endian
- **Connection:** Server on drone, clients (pilot tablet + operator laptop) connect

## Frame Structure

Each CLPC frame consists of a fixed-size header followed by point data payload.

### Header (58 bytes fixed)

| Offset | Field         | Type       | Size | Description                              |
|--------|---------------|------------|------|------------------------------------------|
| 0      | magic         | char[4]    | 4    | "CLPC" - protocol identifier             |
| 4      | version       | uint16     | 2    | Protocol version (= 1)                   |
| 6      | frame_id      | uint32     | 4    | Incrementing frame counter               |
| 10     | timestamp_us  | uint64     | 8    | Frame timestamp (microseconds, monotonic)|
| 18     | point_count   | uint32     | 4    | Number of points in this frame           |
| 22     | flags         | uint32     | 4    | Bitfield (see Flags section)             |
| 26     | pose_x        | float32    | 4    | Drone position X in map frame (ENU, m)   |
| 30     | pose_y        | float32    | 4    | Drone position Y in map frame (ENU, m)   |
| 34     | pose_z        | float32    | 4    | Drone position Z in map frame (ENU, m)   |
| 38     | pose_qw       | float32    | 4    | Drone orientation quaternion W           |
| 42     | pose_qx       | float32    | 4    | Drone orientation quaternion X           |
| 46     | pose_qy       | float32    | 4    | Drone orientation quaternion Y           |
| 50     | pose_qz       | float32    | 4    | Drone orientation quaternion Z           |
| 54     | voxel_size    | float32    | 4    | Current voxel size in meters             |

**Total header size: 58 bytes**

### Flags Bitfield

| Bit | Name               | Description                                |
|-----|--------------------|--------------------------------------------|
| 0   | HAS_INTENSITY      | If set, each point has intensity byte      |
| 1   | SIM                | Frame comes from a simulator/synthetic publisher |
| 2   | REPLAY             | Frame comes from bag/log replay            |
| 3-31| Reserved           | Must be zero                               |

### Point Payload

For each point (repeated `point_count` times):

**Without intensity (flags bit 0 = 0):**

| Field | Type       | Size | Description                    |
|-------|------------|------|--------------------------------|
| x     | float32    | 4    | Point X in map frame (m)       |
| y     | float32    | 4    | Point Y in map frame (m)       |
| z     | float32    | 4    | Point Z in map frame (m)       |

**Point size: 12 bytes**

**With intensity (flags bit 0 = 1):**

| Field     | Type       | Size | Description                    |
|-----------|------------|------|--------------------------------|
| x         | float32    | 4    | Point X in map frame (m)       |
| y         | float32    | 4    | Point Y in map frame (m)       |
| z         | float32    | 4    | Point Z in map frame (m)       |
| intensity | uint8      | 1    | Reflectance intensity (0-255)  |

**Point size: 13 bytes**

## Frame Size Calculation

```
frame_size = 58 + point_count * point_size
where point_size = 12 (no intensity) or 13 (with intensity)
```

For typical operation (voxel 30cm, 2 Hz, ~2000 points with intensity):
```
frame_size = 58 + 2000 * 13 = 26058 bytes (~26 KB)
```

## Coordinate System

- **Map Frame:** ENU (East-North-Up)
- **Origin:** SLAM initialization point
- **Units:** Meters
- **Quaternion Order:** W, X, Y, Z (scalar first)

## Connection Flow

1. Client connects to TCP port 7777
2. Server immediately starts streaming frames at configured rate
3. Client parses frames continuously
4. Connection loss: client should reconnect with backoff

## Error Handling

- **Invalid magic:** Discard bytes until valid "CLPC" found
- **Version mismatch:** Log warning, attempt to parse if version > 1
- **Truncated frame:** Wait for more data or reconnect
- **Timestamp regression:** Accept frame (clock might wrap)

## Link Status Detection

Client should track:
- `lastFrameTime`: timestamp of last successfully parsed frame
- `link_state`: `OK` if frame age < 700 ms, `LAG` for 700-1000 ms, `STALE` for > 1000 ms while TCP is connected, `LOST` when TCP is disconnected

## Future Extensions (Reserved)

- Fragmentation for large frames (fragment_index, fragment_count)
- Compression (future reserved flag)
- Measurement metadata (surface normal, confidence)
- Multiple point types (RGB, semantic labels)

## Reference Implementation

- **Publisher (synthetic):** `scripts/phase3c/clpc_synthetic_publisher.py`
- **Receiver (QGC):** `custom/src/CustomPointCloudReceiver.cc`
- **On-board (future):** `colibri_stream_server` on Radxa/OrangePi

## Version History

| Version | Date       | Changes                          |
|---------|------------|----------------------------------|
| 1       | 2026-06-05 | Initial MVP specification        |
| 1       | 2026-06-06 | Define source flags bit1 `SIM`, bit2 `REPLAY`; document QGC.7 link states |
