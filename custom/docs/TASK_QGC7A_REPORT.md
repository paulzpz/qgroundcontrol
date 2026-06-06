# TASK-QGC.7A Report - Mission-Aware Proximity Thresholds

## Files Changed

- `custom/src/CustomStatusReceiver.h`
- `custom/src/CustomStatusReceiver.cc`
- `custom/src/PointCloudView.qml`

Related files already present from QGC.7 are consumed, not duplicated: `sectorsM`, `frontM`, `missionState`, and `missionStage` still come from `CustomStatusReceiver`.

## Stage To Context Mapping

Implemented in `CustomStatusReceiver::proximityContextFor(...)`; the method is side-effect free and exposed as `Q_INVOKABLE` for direct test coverage.

| mission state | mission stage | context |
|---|---|---|
| IDLE | any | FREE_FLIGHT |
| ARMED | any | FREE_FLIGHT |
| RUN | empty | FREE_FLIGHT |
| RUN | NEXT | FREE_FLIGHT |
| RUN | APPROACH | APPROACH_SURFACE |
| RUN | ALIGN | APPROACH_SURFACE |
| RUN | PRESS | CONTACT_EXPECTED |
| RUN | HOLD | CONTACT_EXPECTED |
| RUN | EXTEND | CONTACT_EXPECTED |
| RUN | MEASURE | CONTACT_EXPECTED |
| RUN | RETRACT | CONTACT_EXPECTED |
| RUN | RELEASE | RETREAT |
| any | unknown | FREE_FLIGHT |

CLST stale behavior: `proximityContext()` keeps the last parsed context while the last status age is <= 2000 ms, then returns FREE_FLIGHT. If the link is not alive or distance is invalid, color output is gray.

## Threshold Table Implemented

Single source of truth: `PROXIMITY_THRESHOLDS[]` in `custom/src/CustomStatusReceiver.cc`. Both the ring sectors and front numeric readout call `CustomStatusReceiver::proximityColor(...)` through `PointCloudView.qml`, so both consume the same threshold table.

| context | red | yellow | blue | green |
|---|---:|---:|---:|---:|
| FREE_FLIGHT | < 0.7 m | <= 2.5 m | none | > 2.5 m |
| APPROACH_SURFACE | < 0.25 m | <= 0.7 m | none | > 0.7 m |
| CONTACT_EXPECTED | < 0.15 m | none | 0.15-0.45 m | > 0.45 m |
| RETREAT | < 0.25 m | <= 0.7 m | none | > 0.7 m |

Blue color: `#4682b4`. Side/rear sectors always pass FREE_FLIGHT into the same color function, regardless of current mission context.

The CONTACT green threshold treats values above the blue contact band as green, matching the task note that there is no yellow lost-contact warning in CONTACT_EXPECTED.

## Visual Changes

- Added 11 px context label near the proximity ring: FREE / APPROACH / CONTACT / RETREAT.
- Ring sectors call `proximityColorForSector(i, d)`.
- Front readout calls the same sector 0 color function as the ring.

## Test Matrix

| # | Case | Result |
|---|---|---|
| 1 | IDLE / ARMED, front around 2.0 m | Synthetic runtime reached IDLE/ARMED; mapping is FREE_FLIGHT. Visual screenshot pending. |
| 2 | APPROACH 2.0 to 0.5 m | Synthetic runtime reached APPROACH/ALIGN; thresholds implemented as green then yellow above 0.25 m. Visual screenshot pending. |
| 3 | PRESS/HOLD/MEASURE around 0.25 m | Synthetic runtime reached PRESS/HOLD/MEASURE; CONTACT_EXPECTED maps to blue band 0.15-0.45 m. Visual screenshot pending. |
| 4 | RELEASE 0.25 to 2.0 m | Mapping implemented; runtime did not run long enough to reach RELEASE in this smoke. |
| 5 | HOLD with front 0.10 m | Hard floor implemented as red below 0.15 m; synthetic edit not performed. |
| 6 | Kill CLST mid-HOLD | Stale hold implemented with 2000 ms context hold, then FREE_FLIGHT; manual visual pass pending. |
| 7 | Unknown stage string | Mapping implemented as FREE_FLIGHT; synthetic edit not performed. |

Screenshots were not captured in this headless session.

## Verification

- `cmake --build /home/paulzp/qgroundcontrol/build --target InnovatechControl -j 4` - pass.
- `cmake --build /home/paulzp/qgroundcontrol/build-custom --target InnovatechControl -j 4` - pass.
- `qmlformat -i custom/src/PointCloudView.qml custom/src/PreflightChecklistDialog.qml custom/src/FlyViewCustomLayer.qml custom/src/InspectionProjectDialog.qml` - pass.
- `qmllint custom/src/PointCloudView.qml custom/src/PreflightChecklistDialog.qml custom/src/FlyViewCustomLayer.qml custom/src/InspectionProjectDialog.qml` - exit 0; warnings are unresolved QGC import paths in standalone lint.
- Marker-token grep - no matches.
- Offscreen runtime smoke without publishers - no ReferenceError, TypeError, SyntaxError, assignment errors, or binding loops in the checked log.
- Offscreen runtime smoke with CLPC/CLST synthetic publishers - QGC connected to both streams and logged CLST stages IDLE, ARMED, APPROACH, ALIGN, PRESS, HOLD, EXTEND, MEASURE plus CLPC SIM frames; no checked runtime error patterns.

## Known Issues

- Visual screenshots remain an operator/manual acceptance item.
- No dedicated Qt test target was added; the context function is side-effect free and exposed for future direct unit tests without QML.

## Upgrade Impact

custom-only product code: yes. Core files list: empty. Core markers: no. Merge risk: low; changes stay in `custom/` and consume existing QGC.7 CLST properties. Tested against Stable_V5.0/Qt 6.8.3: yes, via the build and runtime checks above.
