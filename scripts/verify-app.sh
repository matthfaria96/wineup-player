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

# 5 e 6 abrem o app de verdade: em segundo plano (sem roubar o foco), mudo, com biblioteca e pasta
# temporárias (não lê nem grava a biblioteca do usuário). VERIFY_LAUNCH=0 pula essa parte.
if [ "${VERIFY_LAUNCH:-1}" = "1" ]; then
    mkdir -p "$TMP/empty"
    export WINEUP_LIBRARY_PATH="$TMP/library.sqlite" WINEUP_DEFAULT_FOLDER="$TMP/empty" WINEUP_MUTE=1 WINEUP_NO_SCAN=1

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

    # 6. Abertura via LaunchServices (-g: não ativa o app)
    open -g -n --env WINEUP_LIBRARY_PATH="$WINEUP_LIBRARY_PATH" --env WINEUP_DEFAULT_FOLDER="$WINEUP_DEFAULT_FOLDER" \
        --env WINEUP_MUTE=1 --env WINEUP_NO_SCAN=1 "$COPY"
    sleep 3
    pgrep -f "$TMP/Wineup Player.app/Contents/MacOS/Wineup" >/dev/null || fail "app não abriu fora de build/"
else
    # Sem abrir: cada framework precisa ter todas as arquiteturas do executável.
    ARCHS="$(lipo -archs "$COPY/Contents/MacOS/Wineup")"
    for fw in "$COPY"/Contents/Frameworks/*.framework; do
        nome="$(basename "$fw" .framework)"
        bin="$fw/Versions/Current/$nome"; [ -f "$bin" ] || bin="$fw/$nome"
        for arch in $ARCHS; do
            lipo -archs "$bin" | grep -qw "$arch" || fail "$nome.framework sem $arch"
        done
    done
fi

echo "Empacotamento OK"
