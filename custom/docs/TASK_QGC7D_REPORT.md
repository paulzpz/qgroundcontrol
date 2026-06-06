# TASK-QGC.7D Report - Flight Management Gauge

Date: 2026-06-06
Base: Stable_V5.0 / Qt 6.8.3 / Ubuntu 24.04

## Implemented

- Added a display-only flight management gauge to the existing `FlyViewCustomLayer.qml`.
- Gauge shows status word, inspection time left, battery time, return time, color bar, return-estimate method label, remaining-time method label, and safety-buffer slider.
- Implemented estimator in QML only; no QGC core API or onboard protocol changes.
- Remaining time uses battery `timeRemaining` when populated; otherwise falls back to EWMA percent drain after a 60 s data window.
- Return budget uses optional breadcrumb path length when movement samples exist; otherwise falls back to straight-line `distanceToHome` and labels it `return estimate: approximate`.
- CLST gate enforced: missing/stale CLST or `slamStatus == LOST` forces `UNKNOWN`; no confident indoor return number is shown without CLST pose health.
- Safety buffer is persisted through QtCore `Settings` category `InnovatechFlightBudget`, range 0-300 s, step 30 s, default 120 s.

## Files Changed

QGC7D product/custom changes:
- `custom/src/FlyViewCustomLayer.qml`
- `custom/docs/TASK_QGC7D_REPORT.md`

Housekeeping:
- `custom/docs/TASK_QGC7_REPORT.md` was adjusted to remove a literal marker-token mention that polluted the compatibility grep with a false positive.

No scripts were changed for QGC7D.

## Facts Actually Available

MockLink / current source inspection:
- `Vehicle` exposes `batteries()` as a QML list model, and existing custom QML already uses `vehicle.battery.percentRemaining`.
- `VehicleBatteryFactGroup` exposes `percentRemaining`, `timeRemaining`, and `timeRemainingStr`.
- `VehicleBatteryFactGroup` sets `timeRemaining` from MAVLink `BATTERY_STATUS.time_remaining`; a `0` value becomes NaN.
- MockLink publishes two battery status messages and populates both `battery_remaining` and `time_remaining`, so MockLink can drive the gauge through the direct battery-time path without waiting for the EWMA slope window.
- `distanceToHome` is populated only when both current coordinate and home position are valid; otherwise it is NaN.

PX4/hardware expectation:
- If PX4/Radxa provides `BATTERY_STATUS.time_remaining`, the gauge uses it directly.
- If PX4 does not provide usable `time_remaining`, the gauge uses percent drain EWMA after at least 60 s of data.
- If home/local position is unavailable, return budget remains `UNKNOWN`.
- If CLST is stale or SLAM is `LOST`, the whole gauge remains `UNKNOWN` even if battery data exists.

## Constants Deviations

| Parameter | Required | Implemented | Deviation / reason |
|---|---:|---:|---|
| RETURN_SPEED | 1.0 m/s | 1.0 m/s | none |
| LANDING_BUDGET | 30 s | 30 s | none |
| safety_buffer | 120 s, 0-300, step 30 | 120 s, 0-300, step 30 | none |
| EWMA alpha | 0.2 | 0.2 | none |
| min data window | 60 s | 60 s | none |
| SAFE | >180 s | >180 s | none |
| RETURN SOON | 60-180 s | 60-180 s | none |
| RETURN NOW | 0-60 s | 0-60 s | none |
| LAND NOW | <0 s | <0 s | none |
| UNKNOWN | gray | gray | none |
| Widget sizes | 20 px status, 24 px time, 200x8 bar, 11 px label | implemented | none |
| Update rate | 1 Hz | 1 Hz Timer | none |
| Visibility | vehicle connected only | `visible: !!_activeVehicle` | none |
| Breadcrumb | optional, >0.5 m, cap 10000 | implemented | none |

## Verification

Commands run:
- `/home/paulzp/Qt/6.8.3/gcc_64/bin/qmlformat -i custom/src/FlyViewCustomLayer.qml` - pass.
- `/home/paulzp/Qt/6.8.3/gcc_64/bin/qmllint -I /home/paulzp/qgroundcontrol/custom/res -I /home/paulzp/qgroundcontrol/build/qml custom/src/FlyViewCustomLayer.qml` - exit 0. Remaining warnings are runtime import/qmltypes and existing unqualified-access warnings; no parser errors.
- `cmake --build /home/paulzp/qgroundcontrol/build --target InnovatechControl -j 4` - pass.
- `cmake --build /home/paulzp/qgroundcontrol/build-custom --target InnovatechControl -j 4` - pass.
- Marker-prefix grep - no output after removing the earlier report false positive.
- Runtime sanity: launched `build-custom/Debug/InnovatechControl`; log contained no `ReferenceError`, `TypeError`, `SyntaxError`, assignment errors, or QGC7D QML errors. CLPC/CLST connection refused messages were expected because publishers were not running.

## Manual Test Matrix

Screenshots were not captured in this environment. The gauge visual matrix remains an operator pass with MockLink and CLST synthetic.

| # | Result |
|---|---|
| 1 MockLink connected | Not visually executed; source inspection confirms MockLink battery time facts exist |
| 2 battery drains/status transitions | Logic implemented; force with safety buffer during operator pass |
| 3 straight-line mode | Implemented as `return estimate: approximate` before breadcrumb samples exist |
| 4 CLST stopped or SLAM LOST | Logic implemented; runtime visual pass pending |
| 5 safety_buffer slider | Implemented and persisted; visual pass pending |
| 6 no vehicle | Runtime sanity passed; gauge hidden without active vehicle |

Required screenshots still pending: SAFE, RETURN SOON, LAND NOW, UNKNOWN.

Carry-over visual pass still pending from QGC.6/QGC.7:
- QGC.6: Follow full cycle; Top wall-as-line plus 1.0 m grid ruler; 3 point sizes; Zenodo slice.
- QGC.7: CLST kill/restore; CLPC LAG/STALE; ring thresholds; TEST buttons; REPLAY badge.

## Known Issues

- The operator visual pass was not completed here; the report does not claim screenshot-based acceptance.
- MockLink was not enabled from CLI during this run; factual availability was verified from source and build/runtime sanity only.
- Direct battery `timeRemaining` means MockLink can show a confident estimate immediately; the 60 s learning window applies only when `timeRemaining` is unavailable.
- Return-path breadcrumb starts from the current client session; it is not a persistent flight recorder and is display-only.

## Next Task Readiness

QGC.5P remains unblocked. The gauge adds no storage model requirement but produces useful future metadata candidates: safety buffer, return method, and budget status snapshots.

## Upgrade Impact

- custom-only product code: yes.
- QGC core files changed: none.
- Markers present for every core change: not applicable; marker-prefix grep returned no output.
- Expected merge risk: low. QGC7D changed only the custom FlyView QML and reports.
- Tested against Stable_V5.0 / Qt 6.8.3: yes, both build trees passed.
