# TASK-QGC.7C Report - Error Catalog + CLST Error Mapping

## Files Changed

- `custom/res/error_catalog.json`
- `custom/docs/ERROR_CATALOG.md`
- `custom/src/ErrorCatalog.h`
- `custom/src/ErrorCatalog.cc`
- `custom/src/CustomStatusReceiver.h`
- `custom/src/CustomStatusReceiver.cc`
- `custom/src/PointCloudView.qml`
- `custom/CMakeLists.txt`
- `custom/custom.qrc`

The JSON catalog and human markdown catalog were updated together and should stay synchronized.

## Catalog Contents

| code | severity | title | required action | blocks flight | blocks scan | blocks measure | module |
|---|---|---|---|---:|---:|---:|---|
| SURFACE_BAD_ANGLE | warning | Surface angle out of tolerance | Reposition vehicle or select a better contact point before measuring. | false | false | true | Proximity |
| SLAM_LOST | critical | SLAM lost | Stop motion. Hover or hold position, await relocalization, or land. | false | true | true | SLAM |
| CLPC_STALE | warning | Point cloud stale | Check CLPC publisher, network link, and companion CPU load. | false | true | true | CLPC |
| CLST_STALE | warning | Status channel stale | Check CLST publisher and network link. Readiness and flight budget are unreliable. | true | true | true | CLST |
| CLPC_LOST | critical | Point cloud link lost | Restart CLPC publisher or restore network before scanning. | false | true | true | CLPC |
| CLST_LOST | critical | Status link lost | Restore CLST before continuing inspection workflow. | true | true | true | CLST |

## Loader Behavior

`ErrorCatalog` loads `:/Custom/data/error_catalog.json` at startup through Qt resources. Missing or invalid JSON logs a warning and does not crash; errors then render through the unknown-code fallback.

Unknown-code fallback:

- severity: `warning`
- title: raw normalized code
- required_action: `Uncatalogued error - report to engineering`
- uncatalogued: `true`

## UI Mapping

The QGC.7 indication panel now renders active errors as compact two-line cards:

- title line: 13 px bold, severity color.
- action line: 12 px.
- uncatalogued entries are prefixed with `?`.
- raw code is visible in tooltip and in expanded view.
- max visible rows is 3; additional errors show `+N more` and expand/collapse on click.

Severity colors:

| severity | color |
|---|---|
| info | gray `#868e96` |
| warning | yellow `#ffd43b` |
| error | orange `#f08c00` |
| critical | red `#e03131` |

## Readiness Integration

`CustomStatusReceiver` exposes `activeErrors`, `scanBlockedByError`, and `scanBlockReason`. `PointCloudView.scanReadyText()` checks `scanBlockedByError` in the existing shared scan banner logic, so both the banner and the 7B checklist consume the same scan-not-ready reason. The first active catalog entry with `blocks_scan=true` supplies the title as the scan block reason.

## Test Matrix

| # | Case | Result |
|---|---|---|
| 1 | Synthetic ERROR cycle with SURFACE_BAD_ANGLE | Catalog entry implemented; runtime smoke did not run long enough to hit ERROR visual state. |
| 2 | Unknown code | Fallback implemented; synthetic edit not performed. |
| 3 | SLAM_LOST active | `blocks_scan=true` returns `SLAM lost` as scan block reason; synthetic edit/visual pass pending. |
| 4 | Corrupt JSON | Loader has warning + fallback path; corrupt-resource runtime not performed because resource mutation would require a rebuild variant. |
| 5 | 4+ simultaneous errors | QML max-3 plus expandable `+N more` implemented; multi-error visual pass pending. |

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

- Visual screenshots remain an operator/manual acceptance item.
- Synthetic unknown-code and corrupt-resource scenarios were not executed in this session.

## Upgrade Impact

custom-only product code: yes. Core files list: empty. Core markers: no. Merge risk: low; the catalog helper, qrc resource, and UI changes are isolated to `custom/`. Tested against Stable_V5.0/Qt 6.8.3: yes, via the build and runtime checks above.
