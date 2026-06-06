#!/usr/bin/env python3
"""CLST synthetic publisher for TASK-QGC.7.

Streams newline-delimited CLST v1 JSON status objects at 5 Hz.
"""

import argparse
import json
import math
import random
import socket
import threading
import time
from typing import Dict, List

STAGES = [
    "APPROACH", "ALIGN", "PRESS", "HOLD", "EXTEND",
    "MEASURE", "RETRACT", "RELEASE", "NEXT",
]

STAGE_MESSAGES = {
    "APPROACH": "Approaching surface",
    "ALIGN": "Aligning to target",
    "PRESS": "Pressing probe",
    "HOLD": "Holding contact",
    "EXTEND": "Extending measurement head",
    "MEASURE": "Measuring",
    "RETRACT": "Retracting",
    "RELEASE": "Releasing surface",
    "NEXT": "Preparing next target",
}


class CLSTSyntheticPublisher:
    def __init__(self, host: str, port: int, hz: float) -> None:
        self.host = host
        self.port = port
        self.period = 1.0 / hz
        self.running = False
        self.clients: List[socket.socket] = []
        self.clients_lock = threading.Lock()
        self.server_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.server_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.start_time = time.monotonic()

    def _accept_clients(self) -> None:
        while self.running:
            try:
                self.server_socket.settimeout(1.0)
                client, addr = self.server_socket.accept()
                client.setsockopt(socket.IPPROTO_TCP, socket.TCP_NODELAY, 1)
                with self.clients_lock:
                    self.clients.append(client)
                    total = len(self.clients)
                print(f"Client connected from {addr}, total clients: {total}")
            except socket.timeout:
                continue
            except OSError:
                break

    def _cycle_status(self, t: float) -> Dict:
        normal_cycle_s = 3.0 + 2.0 + len(STAGES) * 3.0
        error_s = 3.0
        super_cycle_s = normal_cycle_s * 2.0 + error_s
        s = t % super_cycle_s
        cycle_index = int(t // normal_cycle_s)

        state = "IDLE"
        stage = "IDLE"
        progress = 0.0
        message = "Idle"
        can_abort = False
        errors: List[str] = []

        if s < normal_cycle_s:
            state, stage, progress, message, can_abort = self._normal_status(s)
        elif s < normal_cycle_s * 2.0:
            state, stage, progress, message, can_abort = self._normal_status(s - normal_cycle_s)
        else:
            state = "ERROR"
            stage = "ERROR"
            progress = 0.0
            message = "Surface angle out of tolerance"
            can_abort = True
            errors = ["SURFACE_BAD_ANGLE"]

        front_m = self._front_distance(stage, progress)
        sectors = self._sectors(front_m)
        slam = "DEGRADED" if (s % normal_cycle_s) >= 14.0 and (s % normal_cycle_s) < 16.0 else "OK"
        if state == "ERROR":
            slam = "LOST"

        now = time.monotonic()
        return {
            "version": 1,
            "ts_us": int(now * 1_000_000),
            "source": "SIM",
            "mission": {
                "state": state,
                "stage": stage,
                "progress": round(progress, 3),
                "message": message,
                "can_abort": can_abort,
            },
            "proximity": {
                "sectors_m": sectors,
                "front_m": round(front_m, 2) if front_m >= 0 else -1.0,
            },
            "health": {
                "slam": slam,
                "lidar": state != "ERROR",
                "cpu_pct": round(55.0 + 15.0 * math.sin(t * 0.7), 1),
                "ev_rate_hz": round(10.0 + 0.5 * math.sin(t * 1.3), 2),
                "rec": cycle_index % 2 == 1 and state == "RUN",
            },
            "errors": errors,
        }

    def _normal_status(self, s: float):
        if s < 3.0:
            return "IDLE", "IDLE", 0.0, "Idle", False
        if s < 5.0:
            return "ARMED", "ARMED", (s - 3.0) / 2.0, "Scan armed", True

        run_s = s - 5.0
        idx = min(len(STAGES) - 1, int(run_s // 3.0))
        stage = STAGES[idx]
        progress = (run_s - idx * 3.0) / 3.0
        return "RUN", stage, progress, STAGE_MESSAGES[stage], True

    def _front_distance(self, stage: str, progress: float) -> float:
        if stage == "APPROACH":
            return 2.0 - 1.5 * progress
        if stage in ("PRESS", "HOLD", "MEASURE"):
            return 0.25
        if stage == "RELEASE":
            return 0.25 + 1.75 * progress
        if stage == "ERROR":
            return 0.8
        if stage == "IDLE":
            return 4.0
        return 1.5 + 0.7 * math.sin(progress * math.pi)

    def _sectors(self, front_m: float) -> List[float]:
        sectors: List[float] = []
        for i in range(8):
            if i in (2, 3):
                sectors.append(-1.0)
                continue
            base = front_m if i == 0 else random.uniform(1.0, 8.0)
            sectors.append(round(max(0.15, base + random.uniform(-0.15, 0.15)), 2))
        return sectors

    def _stream(self) -> None:
        frame = 0
        while self.running:
            start = time.monotonic()
            msg = self._cycle_status(start - self.start_time)
            data = (json.dumps(msg, separators=(",", ":")) + "\n").encode("utf-8")

            disconnected = []
            with self.clients_lock:
                for client in self.clients:
                    try:
                        client.sendall(data)
                    except OSError:
                        disconnected.append(client)
                for client in disconnected:
                    self.clients.remove(client)
                    try:
                        client.close()
                    except OSError:
                        pass
                    print(f"Client disconnected, remaining clients: {len(self.clients)}")

            frame += 1
            if frame % 25 == 0:
                mission = msg["mission"]
                print(f"Frame {frame}: {mission['state']}/{mission['stage']} "
                      f"front {msg['proximity']['front_m']} m, clients: {len(self.clients)}")

            elapsed = time.monotonic() - start
            sleep_time = self.period - elapsed
            if sleep_time > 0:
                time.sleep(sleep_time)

    def start(self) -> None:
        self.server_socket.bind((self.host, self.port))
        self.server_socket.listen(5)
        self.running = True
        print(f"CLST Publisher started on {self.host}:{self.port}")
        print(f"Frame rate: {1.0 / self.period:.1f} Hz")
        print("Waiting for clients...")
        threading.Thread(target=self._accept_clients, daemon=True).start()
        try:
            self._stream()
        except KeyboardInterrupt:
            print("\nShutting down...")
        finally:
            self.stop()

    def stop(self) -> None:
        self.running = False
        with self.clients_lock:
            for client in self.clients:
                try:
                    client.close()
                except OSError:
                    pass
            self.clients.clear()
        try:
            self.server_socket.close()
        except OSError:
            pass
        print("CLST Publisher stopped")


def main() -> None:
    parser = argparse.ArgumentParser(description="CLST Synthetic Publisher")
    parser.add_argument("--host", default="127.0.0.1", help="Host address to bind to")
    parser.add_argument("--port", type=int, default=7778, help="TCP port to listen on")
    parser.add_argument("--hz", type=float, default=5.0, help="Status rate in Hz")
    args = parser.parse_args()
    CLSTSyntheticPublisher(args.host, args.port, args.hz).start()


if __name__ == "__main__":
    main()
