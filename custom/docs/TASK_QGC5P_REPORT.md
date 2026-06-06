# TASK-QGC.5P Report - Inspection Project Model

Date: 2026-06-06
Branch: feat/innovatech-custom-layer
Base: Stable_V5.0
Qt: 6.8.3

## Scope Delivered

- Added `InspectionProject` QObject model in `custom/src` with JSON persistence and QML-facing properties.
- Added Client / Site / Asset / Inspection / Flight metadata fields through the inspection JSON and flight JSON schemas.
- Added configurable project base directory stored in QSettings group `[Project]`, key `baseDir`; default is `~/Documents/Innovatech/inspections`.
- Added restore of last selected inspection and last open flight through QSettings keys `lastInspectionId` and `lastFlightId`.
- Added `inspectionSelected` and `activeFlightPath` Q_PROPERTYs for QGC.8 recorder integration.
- Added source tracking while a flight is open by wiring CLPC `frameReceived` and CLST `statusReceived` to `sources_seen` updates.
- Added FlyView current-project chip and dialog entry point.
- Added single QML dialog for selecting existing inspections, creating new inspections, creating flights, and closing flights.
- Added `custom/docs/ERROR_CATALOG.md` seed only; no 7C UI mapping code was added.

## Files Changed

- `custom/CMakeLists.txt`
- `custom/custom.qrc`
- `custom/src/CustomPlugin.h`
- `custom/src/CustomPlugin.cc`
- `custom/src/InspectionProject.h`
- `custom/src/InspectionProject.cc`
- `custom/src/InspectionProjectDialog.qml`
- `custom/src/FlyViewCustomLayer.qml`
- `custom/docs/ERROR_CATALOG.md`
- `custom/docs/TASK_QGC5P_REPORT.md`

## JSON Formats

No data-format deviations from the task spec.

Inspection layout:

```text
<baseDir>/inspection_<inspection_id>/inspection.json
<baseDir>/inspection_<inspection_id>/flight_NNN/flight.json
```

Representative `inspection.json` sample:

```json
{
    "app_version": "v5.0.8-11-g9447d2c60",
    "asset_name": "Tank A #1!",
    "client_name": "Example Client",
    "created_at": "2026-06-06T20:42:00+02:00",
    "inspection_id": "20260606_tank-a-1_01",
    "notes": "North wall baseline pass.",
    "objective": "Repeat thickness inspection",
    "protocol_versions": {
        "clpc": "1",
        "clst": "1"
    },
    "schema_version": 1,
    "site_name": "Example Site",
    "timezone": "Europe/Rome"
}
```

Representative `flight.json` sample:

```json
{
    "companion_id": "companion-01",
    "created_at": "2026-06-06T20:43:00+02:00",
    "flight_id": "001",
    "operator_id": "operator-01",
    "pilot_id": "pilot-01",
    "px4_params_profile": "indoor-close-inspection",
    "sources_seen": [
        "SIM"
    ],
    "status": "open",
    "vehicle_id": "vehicle-01"
}
```

## Manual Test Matrix

| # | Expected | Result |
|---|---|---|
| 1 | Create inspection writes `inspection.json` with protocol versions | Code path implemented; JSON schema verified by source review and build. GUI click not automated in offscreen smoke. |
| 2 | New flight writes `flight_001/flight.json` immediately | Code path implemented; `createFlight()` creates the directory and writes JSON before returning. |
| 3 | Second flight uses `flight_002` | Code path implemented by scanning existing `flight_???` directories. |
| 4 | Restart restores last selection | Implemented through QSettings restore in `InspectionProject` constructor. |
| 5 | No inspection selected shows orange `NO INSPECTION` and `inspectionSelected=false` | Implemented in `chipText()` and FlyView chip color binding; runtime smoke loaded FlyView. |
| 6 | SIM publishers with open flight add `SIM` to `sources_seen` | Wiring implemented for CLPC and CLST sources. SIM publisher runtime pass not run in this automated session. |
| 7 | Asset `Tank A #1!` slug becomes `tank-a-1` | Implemented in `_slugify()`; exposed to QML with `slugForName()`. |
| 8 | Close flight writes status `closed` | Implemented in `closeFlight()` by writing JSON after setting `_flightOpen=false`. |

Screenshots: not captured in this offscreen automated pass. Dialog and active-flight screenshots need an operator visual pass on a display session.

## Verification

- `qmlformat -i custom/src/FlyViewCustomLayer.qml custom/src/InspectionProjectDialog.qml` - pass.
- `qmllint -I custom/res -I build/qml custom/src/FlyViewCustomLayer.qml custom/src/InspectionProjectDialog.qml` - exit 0. Remaining warnings are existing FlyView-style unqualified-access/import warnings; new dialog-specific `project` warnings were removed.
- `cmake --build build --target InnovatechControl -j 4` - pass, linked `Debug/InnovatechControl`.
- `cmake --build build-custom --target InnovatechControl -j 4` - pass, linked `Debug/InnovatechControl`.
- Marker-prefix grep over the repository - no matches.
- Runtime smoke: launched `build-custom/Debug/InnovatechControl` with `QT_QPA_PLATFORM=offscreen`, `QSG_RHI_BACKEND=software`, and `LIBGL_ALWAYS_SOFTWARE=1`; no ReferenceError, TypeError, SyntaxError, assignment errors, InspectionProjectDialog load errors, or Binding loop entries were found. CLPC/CLST connection refused warnings were expected because publishers were not running.

## Known Issues / Residual Risk

- Offscreen smoke cannot click through the dialog or capture the requested screenshots.
- SIM source append into `sources_seen` is wired but not validated with running publishers in this session.
- `qmllint` still reports pre-existing warnings in `FlyViewCustomLayer.qml`, mainly unqualified parent/root property access and local import resolution for `QGroundControl.Palette`.

## Next Task Readiness

QGC.8 is unblocked at the code/API level: metadata directories, `inspectionSelected`, and `activeFlightPath` are available from the custom plugin. Before merging as a release gate, run the operator visual pass with a display session and SIM publishers to capture screenshots and confirm live `sources_seen` values.

ANDROID.0 untouched.

## Upgrade Impact

- custom-only product code: yes.
- QGC core files changed: none.
- markers present for every core change: not applicable; no core changes.
- expected merge risk: low. The change is isolated to `custom/`, registers one custom QObject, adds one QML resource, and does not alter QGC core APIs.
- tested against Stable_V5.0 / Qt 6.8.3: yes.
