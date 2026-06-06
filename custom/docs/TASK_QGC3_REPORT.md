# TASK-QGC.3 Report: Point Cloud Protocol + Synthetic Publisher + Receiver

**Date:** 2026-06-05
**Status:** COMPLETED

---

## Survey 3D Stack (Step 0)

### Summary

QGC v5.0 uses **Qt Quick 3D** (Qt6::Quick3D) for 3D rendering. This is a modern,
declarative 3D API that integrates well with QML.

### Key Findings

1. **Rendering Technology: Qt Quick 3D**
   - The Viewer3D module links against `Qt6::Quick3D`
   - Located in `src/Viewer3D/` with full CMake integration
   - Build flag: `QGC_VIEWER3D` (enabled by default)

2. **Custom Geometry Approach**
   - `Viewer3DTerrainGeometry` extends `QQuick3DGeometry`
   - `CityMapGeometry` extends `QQuick3DGeometry`
   - Both use `setVertexData()` to provide triangle mesh data
   - Geometry is set via QML: `Model { geometry: CustomGeometry { } }`

3. **Scene Structure**
   - `Viewer3D.qml` - Loader wrapper
   - `Viewer3DModel.qml` - Main `View3D` component
   - Uses `Loader3D` for lazy loading of 3D content
   - Camera controls via DragHandler/PinchHandler/WheelHandler

4. **No Native Point Cloud Support**
   - Qt Quick 3D does not have built-in point cloud rendering
   - Options for future point cloud renderer:
     - A) Custom `QQuick3DGeometry` with GL_POINTS (needs custom material/shader)
     - B) Instanced rendering with small sphere/cube models
     - C) Custom QML component with direct OpenGL (QQuickFramebufferObject)

5. **Relevant Files Examined**
   ```
   src/Viewer3D/CMakeLists.txt          # Qt6::Quick3D link
   src/Viewer3D/Viewer3DTerrainGeometry.h  # Example custom geometry
   src/Viewer3D/Viewer3DQml/Viewer3DModel.qml  # Main View3D
   src/QmlControls/TerrainProfile.cc    # QSGGeometryNode (2D only)
   ```

### Recommendation for Render Task (TASK-QGC.4)

Create `PointCloudGeometry` extending `QQuick3DGeometry` with:
- Dynamic vertex buffer updates
- Custom material for point rendering (may need instancing or custom shader)
- Integration with existing Viewer3D scene OR separate View3D for point cloud

---

## CLPC Protocol v1 (Step 1)

**Document:** `custom/docs/CLPC_PROTOCOL.md`

### Final Protocol Specification

```
Header (58 bytes, little-endian):
  Offset  Field         Type        Description
  0       magic         char[4]     "CLPC"
  4       version       uint16      1
  6       frame_id      uint32      Incrementing frame counter
  10      timestamp_us  uint64      Microseconds (monotonic)
  18      point_count   uint32      Points in frame
  22      flags         uint32      Bit 0: HAS_INTENSITY
  26      pose_x        float32     Drone X (ENU, meters)
  30      pose_y        float32     Drone Y
  34      pose_z        float32     Drone Z
  38      pose_qw       float32     Quaternion W
  42      pose_qx       float32     Quaternion X
  46      pose_qy       float32     Quaternion Y
  50      pose_qz       float32     Quaternion Z
  54      voxel_size    float32     Current voxel size (meters)

Point (13 bytes with intensity):
  x, y, z       float32[3]    12 bytes
  intensity     uint8         1 byte

Transport: TCP, port 7777
```

No changes from the initial specification.

---

## Synthetic Publisher (Step 2)

**File:** `scripts/phase3c/clpc_synthetic_publisher.py`

### Features

- Generates synthetic "wall" point cloud at ~0.25m distance
- Simulates slowly moving drone pose
- TCP server on port 7777
- Configurable frame rate (default 2 Hz)
- Supports multiple clients

### Usage

```bash
python3 scripts/phase3c/clpc_synthetic_publisher.py --host 127.0.0.1 --port 7777 --hz 2
```

### Test Output

```
Generated 4356 base wall points
CLPC Publisher started on 127.0.0.1:7777
Frame rate: 2.0 Hz, Voxel size: 0.030 m
Waiting for clients...
Frame 10: 4356 points, pose (0.05, 0.02, 1.55), clients: 1
```

---

## Receiver Implementation (Step 3)

**Files:**
- `custom/src/CustomPointCloudReceiver.h`
- `custom/src/CustomPointCloudReceiver.cc`

### QML-Exposed Properties

| Property          | Type        | Description                    |
|-------------------|-------------|--------------------------------|
| linkAlive         | bool        | True if frames received < 2s   |
| frameId           | uint32      | Current frame ID               |
| pointCount        | uint32      | Points in current frame        |
| dronePose         | QVector3D   | Drone position (x, y, z)       |
| droneOrientation  | QQuaternion | Drone orientation              |
| voxelSize         | float       | Current voxel size             |
| lastFrameAgeMs    | int         | Age of last frame in ms        |
| statusText        | QString     | Human-readable status          |
| connected         | bool        | TCP connection state           |

### Features

- TCP client with auto-reconnect
- Frame parsing with magic validation
- Link timeout detection (2 seconds)
- Point buffer for future renderer
- Registered in `CustomPlugin` as `pointCloudReceiver`

---

## Debug Label (Step 4)

**File:** `custom/src/FlyViewCustomLayer.qml`

Added CLPC debug panel that displays:
- Frame ID and point count
- Drone pose (x, y, z)
- Frame age in milliseconds
- Link status (OK / LOST / DISCONNECTED)

### Visual Appearance

```
Blue when connected:   CLPC: frame 1234 | 2150 pts | pose (0.10, 0.00, 1.52) | age 480 ms | LINK OK
Red when lost:         CLPC: LINK LOST | age 2500 ms
Red when disconnected: CLPC: DISCONNECTED
```

---

## Files Modified/Created

### New Files in `custom/`

```
custom/docs/CLPC_PROTOCOL.md            # Protocol specification
custom/src/CustomPointCloudReceiver.h   # Receiver header
custom/src/CustomPointCloudReceiver.cc  # Receiver implementation
```

### Modified Files in `custom/`

```
custom/CMakeLists.txt                   # Added new source files
custom/src/CustomPlugin.h               # Added pointCloudReceiver property
custom/src/CustomPlugin.cc              # Created receiver, QML registration
custom/src/FlyViewCustomLayer.qml       # Added CLPC debug panel
```

### New Files in `scripts/`

```
scripts/phase3c/clpc_synthetic_publisher.py  # Synthetic publisher
```

---

## Git Status (Isolation Verification)

```
$ git status
Текущая ветка: feat/innovatech-custom-layer
Неотслеживаемые файлы:
  custom/
  scripts/

индекс пуст, но есть неотслеживаемые файлы
```

**Mainline NOT touched** - all changes isolated to `custom/` and `scripts/`.

---

## Build Verification

```bash
cd ~/qgroundcontrol/build-custom
cmake --build . --parallel
# SUCCESS - InnovatechControl built
```

---

## Testing Instructions

1. Start synthetic publisher:
   ```bash
   python3 scripts/phase3c/clpc_synthetic_publisher.py --hz 2
   ```

2. Launch QGC:
   ```bash
   ./build-custom/Debug/InnovatechControl
   ```

3. Verify CLPC debug label shows live data in Fly View

---

## Known Issues

1. **No point cloud rendering** - This task only implements protocol and reception.
   Rendering is TASK-QGC.4.

2. **Fixed server address** - Currently hardcoded to `127.0.0.1:7777`.
   Future: make configurable via settings.

3. **No UDP option** - TCP only for MVP. UDP fragmentation deferred.

---

## Next Steps (Roadmap)

- **TASK-QGC.4:** Point cloud renderer (based on Qt Quick 3D survey)
- **TASK-QGC.5:** Render controls (point size, color mapping)
- **TASK-QGC.6:** View modes (Free/Follow/Top)
- **TASK-OPI.1:** `colibri_stream_server` on Radxa (requires hardware)
