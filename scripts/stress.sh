#!/bin/bash
# Teste de carga: biblioteca sintética grande + arquivos reais, roteiro automático e vigia de travadas.
# Não toca na sua biblioteca nem nas suas preferências: roda uma cópia do app com outro bundle id
# (app.wineup.player.stress), banco próprio, sem som e sem pegar o foco.
# Uso: ./scripts/stress.sh [pasta-de-fixtures]   (N=50000 faixas sintéticas, FILES=5000 arquivos reais)
# ONLY=metadata|files roda só essa parte; PROFILE=1 grava um Time Profiler junto;
# SHOTS=<pasta> guarda imagens das janelas durante o roteiro.
# Precisa do app em build/ (SKIP_TESTS=1 ./scripts/build-app.sh; o teste de reprodução só roda com RUN_SMOKE=1).
set -euo pipefail
cd "$(dirname "$0")/.."
FIX="${1:-${TMPDIR:-/tmp}/wineup-stress}"
N="${N:-50000}"; FILES="${FILES:-5000}"; TIMEOUT="${TIMEOUT:-900}"
APP="$(pwd)/build/Wineup Player.app"
[ -d "$APP" ] || { echo "app não encontrado: $APP"; exit 1; }
BIN="$(swift build -c release --show-bin-path)"
[ -x "$BIN/wineup-demo" ] || swift build -c release --product wineup-demo >/dev/null

mkdir -p "$FIX/runs"
FIX="$(cd "$FIX" && pwd -P)"
if [ ! -s "$FIX/library.pristine.sqlite" ]; then
    rm -rf "$FIX/Biblioteca" "$FIX"/gen.sqlite*; mkdir -p "$FIX/Biblioteca"
    "$BIN/wineup-demo" --synthetic "$N" "$FIX/gen.sqlite" "$FIX/Biblioteca"
    # Junta o WAL num arquivo só (a cópia de cada rodada parte deste).
    sqlite3 "$FIX/gen.sqlite" "VACUUM INTO '$FIX/library.pristine.sqlite'"
    rm -f "$FIX"/gen.sqlite*
fi
[ -d "$FIX/Arquivos" ] || "$BIN/wineup-demo" --fixtures "$FILES" "$FIX/Arquivos"

RUN="$(mktemp -d)"
STRESS_APP="$RUN/Wineup Stress.app"
LOG="$FIX/runs/$(date +%Y%m%d-%H%M%S).log"
cp -R "$APP" "$STRESS_APP"
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier app.wineup.player.stress" "$STRESS_APP/Contents/Info.plist"
codesign --force --deep -s - "$STRESS_APP" >/dev/null 2>&1
cp "$FIX/library.pristine.sqlite" "$RUN/library.sqlite"

app_pid() { pgrep -f "$RUN/Wineup Stress.app/Contents/MacOS/" || true; }
cleanup() {
    local pid; pid="$(app_pid)"
    [ -n "$pid" ] && kill $pid 2>/dev/null
    sleep 1
    defaults delete app.wineup.player.stress >/dev/null 2>&1 || true
    rm -f "$HOME/Library/Preferences/app.wineup.player.stress.plist"
    rm -rf "$HOME/Library/Saved Application State/app.wineup.player.stress.savedState"
    rm -rf "$RUN"
}
trap cleanup EXIT

open -g -n --env WINEUP_LIBRARY_PATH="$RUN/library.sqlite" --env WINEUP_DEFAULT_FOLDER="$FIX/Biblioteca" \
     --env WINEUP_NO_SCAN=1 --env WINEUP_TEST_SCREEN=left --env WINEUP_STRESS=1 \
     --env WINEUP_STRESS_FILES="$FIX/Arquivos" --env WINEUP_HANG_LOG="$LOG" \
     --env WINEUP_PERF_LOG="$LOG.perf" --env WINEUP_STRESS_DELAY="${PROFILE:+8}" \
     --env WINEUP_STRESS_ONLY="${ONLY:-}" --env WINEUP_STRESS_SHOTS="${SHOTS:-}" "$STRESS_APP"

# PROFILE=1: grava um Time Profiler (com os intervalos de cada passo) em $LOG.trace.
if [ -n "${PROFILE:-}" ]; then
    for _ in $(seq 1 20); do [ -n "$(app_pid)" ] && break; sleep 0.5; done
    xcrun xctrace record --template 'Time Profiler' --attach "$(app_pid)" --output "$LOG.trace" >"$LOG.xctrace.txt" 2>&1 &
fi

for _ in $(seq 1 "$TIMEOUT"); do
    grep -q '^== fim ==' "$LOG" 2>/dev/null && break
    sleep 1
done
# O app encerrou: espera o profiler fechar o arquivo.
[ -n "${PROFILE:-}" ] && wait
sed -n '/^== resumo ==/,/^== fim ==/p' "$LOG" | column -t -s $'\t'
echo "log completo: $LOG"
