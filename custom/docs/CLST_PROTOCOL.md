# CLST Protocol v1 - Colibri Status Channel

**Version:** 1.0
**Date:** 2026-06-06
**Status:** Contract for Innovatech Control ground client and future onboard publisher

## Overview

CLST (Colibri Status) is a lightweight status stream from the onboard computer to Innovatech Control. It carries mission state, scan stage, proximity estimates, health signals, source tagging, and error strings. The current desktop implementation is driven by a synthetic publisher; the same protocol is intended for the real onboard publisher.

## Transport

- **Protocol:** TCP
- **Default Port:** 7778
- **Encoding:** UTF-8 newline-delimited JSON objects
- **Rate:** about 5 Hz
- **Connection:** server on drone/onboard computer, one or more ground clients connect

Each JSON object is terminated by `\n`. Clients parse each complete line as one status sample.

## Status Object

Example:

```json
{
  "version": 1,
  "ts_us": 1730000000000,
  "source": "SIM",
  "mission": {
    "state": "RUN",
    "stage": "APPROACH",
    "progress": 0.4,
    "message": "Approaching surface",
    "can_abort": true
  },
  "proximity": {
    "sectors_m": [3.2, 5.0, -1, -1, 8.1, 4.4, 2.0, 1.1],
    "front_m": 1.02
  },
  "health": {
    "slam": "OK",
    "lidar": true,
    "cpu_pct": 58,
    "ev_rate_hz": 10.0,
    "rec": false
  },
  "errors": []
}
```

## Fields

| Field | Type | Required | Description |
|---|---:|:---:|---|
| `version` | integer | yes | Protocol version, currently `1`. |
| `ts_us` | integer | yes | Publisher timestamp in microseconds. |
| `source` | string | yes | `LIVE`, `SIM`, or `REPLAY`. Mandatory in every message. |
| `mission.state` | string | yes | `IDLE`, `ARMED`, `RUN`, or `ERROR`. |
| `mission.stage` | string | yes | Free string rendered as-is by the UI. Synthetic uses `APPROACH`, `ALIGN`, `PRESS`, `HOLD`, `EXTEND`, `MEASURE`, `RETRACT`, `RELEASE`, `NEXT`. |
| `mission.progress` | number | yes | `0.0 ... 1.0`. |
| `mission.message` | string | yes | Operator-facing short status message. |
| `mission.can_abort` | boolean | yes | Whether abort is valid for this state. |
| `proximity.sectors_m` | array[number] | yes | Eight 45-degree sectors, sector 0 = front (+X), clockwise in top view. `-1.0` means no data. |
| `proximity.front_m` | number | yes | Front distance in meters. `-1.0` means no data. |
| `health.slam` | string | yes | `OK`, `DEGRADED`, or `LOST`. |
| `health.lidar` | boolean | yes | LiDAR alive/usable. |
| `health.cpu_pct` | number | yes | Onboard CPU load percent. |
| `health.ev_rate_hz` | number | yes | Event/state-machine update rate. |
| `health.rec` | boolean | yes | Recording active. |
| `errors` | array[string] | yes | Error identifiers. Detailed catalog is intentionally not part of v1. |

## Staleness

The client marks CLST data stale when no valid JSON status object has been received for more than `1.5 s`. A stale panel must gray out and show `NO DATA`. TCP disconnect is also treated as no data until the receiver reconnects and receives a fresh valid status object.

## Command Envelope Spec - Not Implemented

CLST v1 reserves this JSON envelope shape for future command/ack traffic. Innovatech Control does not send commands in TASK-QGC.7.

```json
{
  "command_id": "uuid-or-monotonic-id",
  "type": "ABORT",
  "created_at": 1730000000000,
  "expires_at": 1730000002000,
  "requires_confirmation": true,
  "allowed_when": {"mission_state": ["ARMED", "RUN"]},
  "ack": {"accepted": false, "rejected": true, "reason": "not implemented"}
}
```

Rules reserved for the future command channel:

- `command_id` must be unique enough for deduplication.
- `created_at` and `expires_at` are microsecond timestamps.
- `requires_confirmation` tells the UI whether a human confirmation gate is required.
- `allowed_when` documents sender/receiver preconditions.
- `ack.accepted` and `ack.rejected` are mutually exclusive; `reason` is required for rejection.
- **TASK-QGC.7 does not implement command sending, receiving, or acknowledgment.**

## Reference Implementations

- Synthetic publisher: `scripts/phase3c/clst_synthetic_publisher.py`
- Ground receiver: `custom/src/CustomStatusReceiver.cc`

## Version History

| Version | Date | Changes |
|---|---|---|
| 1 | 2026-06-06 | Initial CLST status schema and command envelope spec. |
