#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/paulzp/qgroundcontrol"
BAG="/home/paulzp/Downloads/rosbag2_2024_04_16-14_17_01/rosbag2_2024_04_16-14_17_01"
VIDEO="/home/paulzp/Downloads/videoplayback.mp4"
QGC_BIN="$ROOT/build/Debug/InnovatechControl"
PYTHON="$ROOT/scripts/phase3c/venv/bin/python"
PUBLISHER="$ROOT/scripts/phase3c/clpc_bag_publisher.py"
SETTINGS="/home/paulzp/.config/Innovatech/InnovatechControl.ini"

QGC_LOG="/tmp/qgc5-innovatechcontrol.log"
CLPC_LOG="/tmp/qgc5-clpc-publisher.log"
VIDEO_LOG="/tmp/qgc5-video-rtp.log"
QGC_PID="/tmp/qgc5-qgc.pid"
CLPC_PID="/tmp/qgc5-clpc-publisher.pid"
VIDEO_PID="/tmp/qgc5-video-rtp.pid"

stop_pid_file() {
    local file="$1"
    if [[ -f "$file" ]]; then
        local pid
        pid="$(cat "$file" 2>/dev/null || true)"
        if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
            kill "$pid" 2>/dev/null || true
        fi
        rm -f "$file"
    fi
}

stop_matching() {
    local pattern="$1"
    local pids
    pids="$(pgrep -f "$pattern" 2>/dev/null || true)"
    if [[ -n "$pids" ]]; then
        while read -r pid; do
            [[ -n "$pid" ]] && kill "$pid" 2>/dev/null || true
        done <<< "$pids"
    fi
}

stop_all() {
    stop_pid_file "$QGC_PID"
    stop_pid_file "$CLPC_PID"
    stop_pid_file "$VIDEO_PID"
    stop_matching "$QGC_BIN"
    stop_matching "clpc_bag_publisher.py --bag $BAG"
    stop_matching "ffmpeg .*videoplayback.mp4.*5600"
}

configure_qgc_video() {
    python3 - "$SETTINGS" <<'PYSETTINGS'
from pathlib import Path
import sys

path = Path(sys.argv[1])
text = path.read_text() if path.exists() else ""

def set_ini_value(text, section, key, value):
    lines = text.splitlines()
    out = []
    in_sec = False
    seen_section = False
    key_done = False
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("[") and stripped.endswith("]"):
            if in_sec and not key_done:
                out.append(f"{key}={value}")
                key_done = True
            in_sec = stripped == f"[{section}]"
            seen_section = seen_section or in_sec
            out.append(line)
            continue
        if in_sec and line.startswith(f"{key}="):
            if not key_done:
                out.append(f"{key}={value}")
                key_done = True
            continue
        out.append(line)
    if in_sec and not key_done:
        out.append(f"{key}={value}")
    if not seen_section:
        out.extend([f"[{section}]", f"{key}={value}"])
    return "\n".join(out) + "\n"

for key, value in [
    ("videoSource", "UDP h.264 Video Stream"),
    ("udpUrl", "0.0.0.0:5600"),
    ("streamEnabled", "true"),
    ("aspectRatio", "1.777777"),
    ("videoFit", "1"),
    ("gridLines", "false"),
    ("lowLatencyMode", "true"),
]:
    text = set_ini_value(text, "Video", key, value)

for key, value in [
    ("MainFlyWindowIsMap", "false"),
    ("IsPIPVisible", "true"),
]:
    text = set_ini_value(text, "QGCQml", key, value)

path.parent.mkdir(parents=True, exist_ok=True)
path.write_text(text)
PYSETTINGS
}

if [[ "${1:-}" == "--stop" ]]; then
    stop_all
    echo "Stopped QGC, CLPC publisher, and RTP video streamer."
    exit 0
fi

for required in "$QGC_BIN" "$PYTHON" "$PUBLISHER" "$VIDEO"; do
    if [[ ! -e "$required" ]]; then
        echo "Missing required file: $required" >&2
        exit 1
    fi
done

stop_all
configure_qgc_video

setsid "$PYTHON" -u "$PUBLISHER" \
    --bag "$BAG" \
    --voxel 0.30 \
    --rate 5 \
    --range-max 30 \
    --loop \
    > "$CLPC_LOG" 2>&1 < /dev/null &
echo $! > "$CLPC_PID"

setsid ffmpeg -hide_banner -loglevel warning \
    -stream_loop -1 \
    -re \
    -i "$VIDEO" \
    -an \
    -vf "format=yuv420p" \
    -c:v libx264 \
    -preset ultrafast \
    -tune zerolatency \
    -profile:v baseline \
    -pix_fmt yuv420p \
    -bf 0 \
    -g 30 \
    -keyint_min 30 \
    -x264-params "repeat-headers=1:scenecut=0" \
    -payload_type 96 \
    -f rtp \
    "udp://127.0.0.1:5600?pkt_size=1200" \
    > "$VIDEO_LOG" 2>&1 < /dev/null &
echo $! > "$VIDEO_PID"

sleep 1

cd "$ROOT"
setsid env QSG_RHI_BACKEND=opengl "$QGC_BIN" \
    > "$QGC_LOG" 2>&1 < /dev/null &
echo $! > "$QGC_PID"

echo "CLPC publisher PID: $(cat "$CLPC_PID")"
echo "RTP video PID:      $(cat "$VIDEO_PID")"
echo "QGC PID:            $(cat "$QGC_PID")"
echo "Logs: $CLPC_LOG, $VIDEO_LOG, $QGC_LOG"
