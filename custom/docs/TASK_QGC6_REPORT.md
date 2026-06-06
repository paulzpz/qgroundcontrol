# TASK-QGC.6 Report - 2026-06-06

## Status

Implementation complete at build/lint level. Manual screenshot acceptance was not captured in this run because the Cloud panel is opened only by an in-app click and this environment has no reliable Wayland GUI automation tool (`xdotool`, `gnome-screenshot`, `grim` absent).

## Implemented

- PointCloudView mode row: `Free`, `Follow`, `Top`.
- `Free`: kept the existing orbit/pan/wheel camera path.
- `Follow`: perspective camera targets `pointCloudReceiver.dronePose`, fixed distance `6.0 m`, fixed pitch `-25 deg`, user azimuth retained from orbit yaw, target EWMA alpha `0.3`.
- `Top`: separate `OrthographicCamera`, camera above cloud bbox center, height/span `1.2 * max(bbox_x, bbox_y)` clamped to `[5.0, 100.0] m`, explicit roll for `+X` map direction toward screen up, wheel changes orthographic magnification rather than camera position, rotate disabled.
- Render controls panel: collapsed gear, expanded width `210 px`, point size slider, color mode toggle, grid toggle, axes toggle, slice toggle, slice height slider. Settings are session-local QML state.
- Slice filtering: CPU-side during point buffer repack in `PointCloudGeometry`, using `abs(z_point - z_drone) <= h/2`; overlay reports `Slice: [z0 ... z1] m, N of M pts`.
- Grid changed from filled rectangle to `PointCloudGridGeometry` line geometry: `20 x 20 m`, `1.0 m` cells, plane `z = 0`.
- Height color EWMA changed to alpha `0.2`; gradient simplified to blue -> green -> red.

## Files Changed

- `custom/src/PointCloudView.qml`
- `custom/src/PointCloudGeometry.h`
- `custom/src/PointCloudGeometry.cc`
- `custom/src/PointCloudGridGeometry.h`
- `custom/src/PointCloudGridGeometry.cc`
- `custom/src/CustomPlugin.cc`
- `custom/CMakeLists.txt`
- `custom/docs/TASK_QGC6_REPORT.md`

## Constants / Deviations

No intentional deviation from TASK-QGC.6 table constants. Changes from QGC.5 defaults:

- Grid size: `100.0 m -> 20.0 m`, reason: QGC.6 table.
- Point size UI range: max `0.05 m -> 0.10 m`, reason: QGC.6 table.
- Height EWMA: `0.1 -> 0.2`, reason: QGC.6 table.
- Top orthographic span uses the same clamped value as Top camera height so no extra meter-scale constant is introduced for ortho magnification.

## Build Trees

Primary build tree used for QGC.6: `/home/paulzp/qgroundcontrol/build`.

Also rebuilt: `/home/paulzp/qgroundcontrol/build-custom`.

Both caches are custom Innovatech builds (`CMAKE_PROJECT_NAME=InnovatechControl`, `QGC_APP_NAME=InnovatechControl`, `QGC_RESOURCES` includes `custom/custom.qrc`). I did not find a remaining vanilla reference build tree in this workspace; both `build/` and `build-custom/` are custom-configured.

## Verification

Passed:

```bash
cmake --build /home/paulzp/qgroundcontrol/build --target InnovatechControl -j 4
cmake --build /home/paulzp/qgroundcontrol/build-custom --target InnovatechControl -j 4
/home/paulzp/Qt/6.8.3/gcc_64/bin/qmlformat custom/src/PointCloudView.qml >/tmp/qgc6_PointCloudView.qml.formatted
```

`qmllint` passed with exit code `0`; remaining warnings are unresolved `Custom.PointCloud` runtime types because they are registered by `InnovatechControl` rather than available as a standalone qmltypes import.

Not captured in this run:

- Free/Follow/Top screenshots on synthetic stream.
- Free/Follow/Top screenshots on Zenodo bag.
- Three point-size screenshots (`0.005`, `0.020`, `0.100 m`).
- Visual confirmation that Follow keeps the drone in frame for a full synthetic cycle.
- Visual confirmation that Top renders the wall as a line and grid cells as `1.0 m`.
- Visual confirmation that Zenodo slice `2.0 m` removes out-of-band points.

## Acceptance Checklist

- [x] Free path preserved in code.
- [x] Follow mode implemented with fixed `6.0 m` distance and `-25 deg` pitch.
- [x] Top mode implemented with `OrthographicCamera`.
- [x] Top rotation disabled; wheel changes ortho magnification.
- [x] Slice implemented CPU-side during buffer repack.
- [x] Slice overlay reports `[z0 ... z1] m, N of M pts`.
- [x] Point size slider range `0.005 ... 0.10 m`, step `0.005`.
- [x] Color mode Intensity/Height live control.
- [x] Grid default on; axes default on.
- [x] Grid geometry `20 x 20 m`, `1.0 m` cells, `z = 0`.
- [x] Height color EWMA alpha `0.2`.
- [x] Builds pass in `build/` and `build-custom/`.
- [ ] Manual screenshot regression.
- [ ] Manual synthetic/Zenodo visual acceptance.

## Git Status

Final status:

```text
?? custom/
?? scripts/
```

Code changes for QGC.6 were made under `custom/`. The untracked `scripts/` tree is pre-existing Phase 3c material from earlier tasks and was not edited for QGC.6.

## Known Issues

- Visual acceptance screenshots still need a manual GUI pass with the Cloud panel open.
- There is no clean vanilla reference build tree in this workspace; both existing build trees are custom InnovatechControl builds.
