#!/bin/bash
# Abre o app empacotado com FLAC, M4A e WAV sintéticos e confirma que não morre nem gera crash report.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-build/Wineup Player.app}"
APP_ABS="$(cd "$(dirname "$APP")" && pwd)/$(basename "$APP")"
PATTERN="Wineup Player.app/Contents/MacOS/Wineup"

fail() { echo "ERRO: $1" >&2; exit 1; }

TMP="$(mktemp -d)"
LIB_TMP="$(mktemp -d)"
export WINEUP_LIBRARY_PATH="$LIB_TMP/library.sqlite"
trap 'rm -rf "$LIB_TMP"; pkill -f "$PATTERN" || true; rm -rf "$TMP"' EXIT

python3 -I -c '
import sys, wave, math, struct
w = wave.open(sys.argv[1], "wb")
w.setnchannels(1); w.setsampwidth(2); w.setframerate(44100)
w.writeframes(b"".join(struct.pack("<h", int(12000*math.sin(2*math.pi*440*i/44100))) for i in range(44100*3)))
w.close()
' "$TMP/sine.wav"
afconvert -f flac -d flac "$TMP/sine.wav" "$TMP/sine.flac"
afconvert -f m4af -d aac "$TMP/sine.wav" "$TMP/sine.m4a"

for f in sine.flac sine.m4a sine.wav; do
    BEFORE=$({ find ~/Library/Logs/DiagnosticReports -maxdepth 1 -name "Wineup-*.ips" 2>/dev/null || true; } | wc -l | tr -d " ")
    # Em segundo plano (-g) e sem som (WINEUP_MUTE): não toma o foco, não toca alto e não grava sessão.
    open -g -n --env WINEUP_LIBRARY_PATH="$WINEUP_LIBRARY_PATH" --env WINEUP_MUTE=1 -a "$APP_ABS" "$TMP/$f"
    sleep 5
    pgrep -f "$PATTERN" >/dev/null || fail "app morreu tocando $f"
    AFTER=$({ find ~/Library/Logs/DiagnosticReports -maxdepth 1 -name "Wineup-*.ips" 2>/dev/null || true; } | wc -l | tr -d " ")
    [ "$AFTER" -eq "$BEFORE" ] || fail "crash report novo ao tocar $f"
    pkill -f "$PATTERN" || true
    sleep 1
done

echo "Reprodução OK (FLAC, M4A, WAV)"
