#!/bin/bash
# Valida o empacotamento do .app: rpath, frameworks embutidos, assinatura e abertura fora de build/.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-build/Wineup Player.app}"
BIN="$APP/Contents/MacOS/Wineup"
FWDIR="$APP/Contents/Frameworks"

fail() { echo "ERRO: $1" >&2; exit 1; }

[ -x "$BIN" ] || fail "binário não encontrado em $BIN"

# 1. rpath
otool -l "$BIN" | grep -A2 LC_RPATH | grep -q "@executable_path/../Frameworks" || fail "rpath ausente"

# 2. Frameworks referenciados precisam estar embutidos
check_deps() {
    local file="$1" dep name
    while IFS= read -r dep; do
        name="${dep#@rpath/}"
        name="${name%%/*}"
        case "$name" in
            *.framework)
                [ -d "$FWDIR/$name" ] || fail "$file referencia $name, que não está em Contents/Frameworks"
                ;;
        esac
    done < <(otool -L "$file" | tail -n +2 | awk '{print $1}' | grep '^@rpath/' || true)
}
check_deps "$BIN"
for fw in "$FWDIR"/*.framework; do
    [ -d "$fw" ] || continue
    nome="$(basename "$fw" .framework)"
    if [ -f "$fw/Versions/Current/$nome" ]; then
        check_deps "$fw/Versions/Current/$nome"
    elif [ -f "$fw/$nome" ]; then
        check_deps "$fw/$nome"
    fi
done

# 3. Assinatura
codesign --verify --deep --strict "$APP" || fail "assinatura inválida"

# 4. Cópia fora de build/
TMP="$(mktemp -d)"
COPY="$TMP/Wineup Player.app"
trap 'pkill -f "$TMP/Wineup Player.app/Contents/MacOS/Wineup" || true; rm -rf "$TMP"' EXIT
ditto "$APP" "$COPY"

# 5. dyld direto
"$COPY/Contents/MacOS/Wineup" >"$TMP/direct.log" 2>&1 &
PID=$!
sleep 3
if ! kill -0 "$PID" 2>/dev/null; then
    if grep -qE "Library not loaded|dyld" "$TMP/direct.log"; then
        fail "dyld não resolveu frameworks"
    fi
else
    kill "$PID" 2>/dev/null || true
    wait "$PID" 2>/dev/null || true
fi

# 6. Abertura via LaunchServices
open -n "$COPY"
sleep 3
pgrep -f "$TMP/Wineup Player.app/Contents/MacOS/Wineup" >/dev/null || fail "app não abriu fora de build/"

echo "Empacotamento OK"
