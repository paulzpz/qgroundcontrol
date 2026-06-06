# TASK-QGC.7B Report - Preflight / Scan Checklist

## Files Changed

- `custom/src/PreflightChecklistDialog.qml`
- `custom/src/PointCloudView.qml`
- `custom/src/InspectionProject.h`
- `custom/src/InspectionProject.cc`
- `custom/custom.qrc`

QGC.5P inspection project files are used by this task; `baseDirFreeGb()` was added to expose filesystem free space at `[Project] baseDir` to QML.

## UI Summary

- Dialog width is capped at 420 px.
- Checklist row height is 28 px.
- Status icon is 16 px.
- Verdict text is 20 px bold.
- Dialog opens from a `CHECKLIST` button placed next to the existing flight readiness banner in the QGC.7 point-cloud panel.
- Dialog refreshes with QML bindings plus a 1 Hz timer used only for values that need periodic reevaluation, such as storage space and live readiness text.

## Reuse Proof

The top verdict calls the existing banner methods through `host.flightReadyText()` and `host.scanReadyText()` instead of reimplementing their aggregate logic. The checklist adds QGC.5P-only scan checks inside the dialog: inspection selected and SIM source warning.

| line | source consumed |
|---|---|
| PX4 connected | `QGroundControl.multiVehicleManager.activeVehicle` |
| RC/H16 link OK | `activeVehicle.vehicleLinkManager.communicationLost` |
| Video stream receiving | `QGroundControl.videoManager.streaming`, `decoding`, `hasVideo` |
| CLPC OK | `pointCloudReceiver.linkState` from QGC.7 |
| CLST OK | `statusReceiver.linkAlive` from QGC.7 |
| LIDAR OK | `statusReceiver.lidarAlive` from QGC.7 |
| SLAM OK | `statusReceiver.slamStatus` from QGC.7 |
| Battery > 20% | `activeVehicle.battery.percentRemaining`, with batteries-list fallback in dialog |
| Storage free >= 5 GB | `inspectionProject.baseDirFreeGb()` over `[Project] baseDir` |
| Inspection selected | `inspectionProject.inspectionSelected` from QGC.5P |
| Source != SIM | active CLPC/CLST `source` values from QGC.7 |

SIM remains nonblocking: the line is orange and the verdict adds `(SIM)` when any active source is SIM.

## Verdict Rules

- If `flightReadyText()` is not `FLIGHT READY`, the dialog shows `NOT READY: <reason>`.
- If flight is ready but scan readiness or inspection selection is not complete, the dialog shows `READY TO FLY`.
- If flight, scan, and inspection selection are all ready, the dialog shows `READY TO SCAN`.
- If SIM is active, the verdict suffix is `(SIM)` and color is orange.

## Test Matrix

| # | Case | Result |
|---|---|---|
| 1 | Synthetic up, no real vehicle | Runtime smoke confirms CLPC/CLST connect; no vehicle case remains `NOT READY: PX4 not connected` by existing banner logic. Visual screenshot pending. |
| 2 | Kill CLST | Logic implemented: CLST row gray/no-data; LIDAR and SLAM rows gray/no-data. Manual visual pass pending. |
| 3 | No inspection selected | Logic implemented: inspection line red with reason `no inspection selected`; verdict remains `READY TO FLY` if flight is otherwise ready. |
| 4 | SIM sources active | Synthetic CLPC/CLST advertise SIM; dialog line and verdict suffix implemented. Visual screenshot pending. |
| 5 | baseDir full or threshold raised | Storage free check implemented via `QStorageInfo`; full-disk scenario not executed. |
| 6 | Open during stage cycling | Synthetic runtime ran through multiple stages without checked QML runtime errors. Manual visible flicker pass pending. |

Screenshots were not captured in this headless session.

## Verification

- `cmake --build /home/paulzp/qgroundcontrol/build --target InnovatechControl -j 4` - pass.
- `cmake --build /home/paulzp/qgroundcontrol/build-custom --target InnovatechControl -j 4` - pass.
- `qmlformat -i custom/src/PointCloudView.qml custom/src/PreflightChecklistDialog.qml custom/src/FlyViewCustomLayer.qml custom/src/InspectionProjectDialog.qml` - pass.
- `qmllint custom/src/PointCloudView.qml custom/src/PreflightChecklistDialog.qml custom/src/FlyViewCustomLayer.qml custom/src/InspectionProjectDialog.qml` - exit 0; warnings are unresolved QGC import paths in standalone lint.
- Marker-token grep - no matches.
- Offscreen runtime smoke without publishers - no ReferenceError, TypeError, SyntaxError, assignment errors, or binding loops in the checked log.
- Offscreen runtime smoke with CLPC/CLST synthetic publishers - QGC connected to both streams and logged live CLPC frames plus CLST stage updates; no checked runtime error patterns.

## Known Issues

- The optional auto-show on New flight was not added; the requested primary entry point next to the readiness banner is implemented.
- Visual screenshots remain an operator/manual acceptance item.

## Upgrade Impact

custom-only product code: yes. Core files list: empty. Core markers: no. Merge risk: low; UI and storage helper stay in `custom/` and reuse existing QGC.7/QGC.5P state. Tested against Stable_V5.0/Qt 6.8.3: yes, via the build and runtime checks above.
