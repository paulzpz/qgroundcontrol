# Innovatech Error Catalog

Status: living document. Populated as real CLST and client errors appear. UI mapping is QGC.7C. Keep this document and `custom/res/error_catalog.json` synchronized.

| code | severity | title | required_action | blocks_flight | blocks_scan | blocks_measure | module |
|---|---|---|---|---:|---:|---:|---|
| SURFACE_BAD_ANGLE | warning | Surface angle out of tolerance | Reposition vehicle or select a better contact point before measuring. | false | false | true | Proximity |
| SLAM_LOST | critical | SLAM lost | Stop motion. Hover or hold position, await relocalization, or land. | false | true | true | SLAM |
| CLPC_STALE | warning | Point cloud stale | Check CLPC publisher, network link, and companion CPU load. | false | true | true | CLPC |
| CLST_STALE | warning | Status channel stale | Check CLST publisher and network link. Readiness and flight budget are unreliable. | true | true | true | CLST |
| CLPC_LOST | critical | Point cloud link lost | Restart CLPC publisher or restore network before scanning. | false | true | true | CLPC |
| CLST_LOST | critical | Status link lost | Restore CLST before continuing inspection workflow. | true | true | true | CLST |
