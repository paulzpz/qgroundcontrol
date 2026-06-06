# TASK-QGC.7 Report - CLST Status, Readiness, Staleness, Source, Network

Date: 2026-06-06
Base: Stable_V5.0 / Qt 6.8.3 / Ubuntu 24.04

## Implemented

- Added CLST v1 protocol documentation with newline-delimited JSON over TCP `:7778` and command envelope marked `SPEC ONLY / NOT IMPLEMENTED`.
- Added `CustomStatusReceiver` in `custom/`: QTcpSocket client, line-buffered JSON parser, auto-reconnect, 1.5 s stale policy, QSettings-backed host/port, async TCP TEST probe.
- Extended CLPC receiver: source flags `SIM`/`REPLAY`, QSettings-backed host/port, async TEST probe, age-based `OK`/`LAG`/`STALE`/`LOST`, latest-frame-wins parsing.
- Added CLST health/readiness/stage/proximity/source/settings UI in the existing Cloud view; extended the existing Fly view CLPC debug label.
- Updated CLPC protocol flags: bit0 `HAS_INTENSITY`, bit1 `SIM`, bit2 `REPLAY`.
- Updated publishers: synthetic CLPC sets `SIM`, bag player sets `REPLAY`, new CLST synthetic publisher cycles IDLE/ARMED/RUN stages plus ERROR.
- Carried over QGC.6 view-control fixes: existing controls only, Top remains orthographic, slice now has center offset plus thickness.

## Files Changed

Product/custom layer:
- `custom/CMakeLists.txt`
- `custom/src/CustomPlugin.h`
- `custom/src/CustomPlugin.cc`
- `custom/src/CustomPointCloudReceiver.h`
- `custom/src/CustomPointCloudReceiver.cc`
- `custom/src/CustomStatusReceiver.h`
- `custom/src/CustomStatusReceiver.cc`
- `custom/src/FlyViewCustomLayer.qml`
- `custom/src/PointCloudGeometry.h`
- `custom/src/PointCloudGeometry.cc`
- `custom/src/PointCloudView.qml`
- `custom/docs/CLPC_PROTOCOL.md`
- `custom/docs/CLST_PROTOCOL.md`
- `custom/docs/TASK_QGC7_REPORT.md`

Development/smoke scripts required by the task:
- `scripts/phase3c/clpc_synthetic_publisher.py`
- `scripts/phase3c/clpc_bag_publisher.py`
- `scripts/phase3c/clst_synthetic_publisher.py`

## CLST Schema Deviations

No schema deviation from TASK-QGC.7 section 5.

The command envelope is documented in `CLST_PROTOCOL.md` as specification only and is not implemented, per task scope.

## Constants Deviations

| Element | Required | Implemented | Deviation / reason |
|---|---:|---:|---|
| CLST synthetic rate | 5 Hz | 5 Hz default | none |
| CLST stale | 1.5 s | 1500 ms | none |
| CLPC OK/LAG/STALE/LOST | <700 / 700-1000 / >1000 / disconnected | implemented | none |
| TEST timeout | 2.0 s | 2000 ms | none |
| Health chip height | 26 px | 26 px | none |
| Readiness text | 20 pt bold | 20 px bold QML font | QML uses pixelSize; visual target preserved |
| Stage text/message/progress | 24 pt / 13 pt / 240x6 | 24 px / 13 px / 240x6 | QML uses pixelSize; visual target preserved |
| Proximity ring | 150 px | 150 px | none |
| Front distance | 28 pt | 28 px QML font | QML uses pixelSize; visual target preserved |
| Settings defaults | 127.0.0.1:7777 / 127.0.0.1:7778 | named default constants loaded through QSettings | no startup hardcoded connect remains; defaults intentionally remain as task defaults |
| QGC.6 slice controls | offset 0.0 [-5,+5], thickness 1.0 [0.1,5.0] | implemented | replaced earlier single `sliceHeight` control with offset + thickness per carry-over task |

## Verification

Commands run:
- `/home/paulzp/Qt/6.8.3/gcc_64/bin/qmlformat -i custom/src/PointCloudView.qml custom/src/FlyViewCustomLayer.qml` - pass.
- `/home/paulzp/Qt/6.8.3/gcc_64/bin/qmllint -I /home/paulzp/qgroundcontrol/custom/res -I /home/paulzp/qgroundcontrol/build/qml custom/src/PointCloudView.qml custom/src/FlyViewCustomLayer.qml` - exit 0. Remaining warnings are runtime import/qmltypes and existing unqualified-access warnings; no parser errors.
- `python3 -m py_compile scripts/phase3c/clpc_synthetic_publisher.py scripts/phase3c/clpc_bag_publisher.py scripts/phase3c/clst_synthetic_publisher.py` - pass.
- `cmake --build /home/paulzp/qgroundcontrol/build --target InnovatechControl -j 4` - pass.
- `cmake --build /home/paulzp/qgroundcontrol/build-custom --target InnovatechControl -j 4` - pass.
- `rg -n <Innovatech patch marker prefix> .` - no output.

Smoke run:
- Started CLPC synthetic on `127.0.0.1:7777`, CLST synthetic on `127.0.0.1:7778`, and `build-custom/Debug/InnovatechControl`.
- QGC log confirmed `Connected to CLPC server` and `Connected to CLST server`.
- QGC log confirmed CLPC frames like `4356 points "SIM"`.
- QGC log confirmed CLST stages `IDLE`, `ARMED`, `RUN/APPROACH`, `RUN/MEASURE`, `RUN/RETRACT`, and ERROR cycle `CLST "ERROR" "ERROR" "SIM"`.
- QGC log confirmed `PointCloudView loaded`.
- Smoke processes were stopped after the run.

## Manual Test Matrix

Screenshots were not captured in this environment. Visual acceptance remains an operator pass; runtime smoke evidence is recorded above.

| # | Result |
|---|---|
| 1 start CLST + CLPC, open Cloud | Runtime pass; visual screenshot pending |
| 2 ERROR cycle arrives | Runtime pass; visual screenshot pending |
| 3 kill CLST publisher | Not visually executed; stale gray/no-data requires operator pass |
| 4 kill CLPC publisher | Not visually executed; LOST/recover requires operator pass |
| 5 throttle CLPC to 0.5 Hz | Not executed; operator pass pending |
| 6 front_m red/yellow/green thresholds | Synthetic data implemented; visual pass pending |
| 7 sectors with -1 | Synthetic data implemented; visual pass pending |
| 8 SIM badge | Source `SIM` received in both channels; visual pass pending |
| 9 bag player REPLAY badge | REPLAY flag implemented and py_compile pass; operator pass pending |
| 10 wrong/fixed CLST port TEST | UI/probe implemented; manual operator pass pending |
| 11 CLPC + CLST + video | CLPC+CLST runtime pass; video/FPS subjective pass pending |
| 12 readiness | Logic implemented; PX4-absent visual pass pending |

Carry-over QGC.6 visual pass is still open: Follow full cycle, Top wall-as-line plus 1.0 m grid ruler, three point sizes, and Zenodo slice still need operator screenshots.

## Known Issues

- No real onboard CLST publisher exists yet; synthetic publisher is the protocol contract driver for now.
- Command channel is protocol documentation only, intentionally not implemented.
- `qmllint` cannot resolve some runtime QGC/custom qmltypes in this command-line context, but exits 0 and reports no parser errors.
- Runtime log still reports missing `qrc:/res/InnovatechLogo.svg`; this is unrelated to QGC.7 and was not changed here.

## Next Task Readiness

- QGC.5P is not blocked by QGC.7; protocol_versions `{CLPC, CLST}` can now be recorded in the future inspection model.
- ANDROID.0 remains a hardware/APK feasibility spike; QGC.7 did not add non-custom core coupling, but Qt Quick 3D performance still needs H16 validation.

## Upgrade Impact

- custom-only: no, because task-required development publishers under `scripts/phase3c/` changed. Product/runtime QGC code remains inside `custom/`.
- QGC core files changed: none.
- Innovatech patch markers present for every core change: not applicable; `rg -n <Innovatech patch marker prefix> .` returned no output.
- Expected merge risk: low. No QGC core files were modified; merge surface is limited to `custom/` and dev scripts.
- Tested against current QGC base (Stable_V5.0 / Qt 6.8.3): yes, both `build` and `build-custom` target builds passed.
