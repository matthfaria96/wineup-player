#!/bin/bash
# Testes de interface com cliques reais, numa biblioteca de demonstração temporária.
# Não toca na sua biblioteca; salva e restaura as preferências do app.
# Requer: app em build/, permissão de Acessibilidade para o Terminal/Claude.
set -uo pipefail
cd "$(dirname "$0")/.."
APP="$(pwd)/build/Wineup Player.app"
TMP="$(mktemp -d)"; LIB="$TMP/Biblioteca"; DB="$TMP/library.sqlite"; PREFS="$TMP/prefs.plist"
mkdir -p "$LIB"
[ -x scripts/tools/click ] || swiftc -O -o scripts/tools/click scripts/tools/click.swift
defaults export app.wineup.player "$PREFS" 2>/dev/null || true
cleanup() {
    pkill -x Wineup 2>/dev/null; sleep 1
    defaults delete app.wineup.player 2>/dev/null; [ -s "$PREFS" ] && defaults import app.wineup.player "$PREFS"
    rm -rf "$TMP"
}
trap cleanup EXIT

WINEUP_LIBRARY_PATH="$DB" WINEUP_DEFAULT_FOLDER="$LIB" \
    "$(swift build -c release --show-bin-path)/wineup-demo" "$LIB" >/dev/null 2>&1
# Show dividido por CUE: o arquivo inteiro fica escondido e vira 2 faixas.
mkdir -p "$LIB/Show"
cp "$(find "$LIB" -name '*Abertura do Vinho.flac' | head -1)" "$LIB/Show/show.flac"
printf 'PERFORMER "Os Taninos"\nTITLE "Ao Vivo"\nFILE "show.flac" WAVE\n  TRACK 01 AUDIO\n    TITLE "Parte Um"\n    INDEX 01 00:00:00\n  TRACK 02 AUDIO\n    TITLE "Parte Dois"\n    INDEX 01 00:15:00\n' > "$LIB/Show/show.cue"
WINEUP_LIBRARY_PATH="$DB" WINEUP_DEFAULT_FOLDER="$LIB" \
    "$(swift build -c release --show-bin-path)/wineup-demo" "$LIB" >/dev/null 2>&1
defaults write app.wineup.player viewMode songs
defaults write app.wineup.player layoutMode.v2 standard
pkill -x Wineup 2>/dev/null; sleep 1
open -n --env WINEUP_LIBRARY_PATH="$DB" --env WINEUP_DEFAULT_FOLDER="$LIB" "$APP"
sleep 6

W='window "Wineup Player"'
ax() { osascript -e "tell application \"System Events\" to tell process \"Wineup\" to $1" 2>/dev/null; }
contents() { osascript -e "tell application \"System Events\" to tell process \"Wineup\" to get entire contents of $W" 2>/dev/null; }
has() {
    # Espera até ~15 s: cargas e varreduras são assíncronas.
    for _ in $(seq 1 15); do contents | grep -qF "static text $1 of" && return 0; sleep 1; done
    return 1
}
click_at() { ./scripts/tools/click "$1" "$2"; sleep "${3:-1.5}"; }
click_text() {
    local p
    p=$(ax "get position of static text \"$1\" of UI element 1 of scroll area 1 of group 1 of $W" | tr -d ' ')
    [[ "$p" =~ ^[0-9]+,[0-9]+$ ]] || p=$(ax "get position of static text \"$1\" of group 1 of $W" | tr -d ' ')
    [[ "$p" =~ ^[0-9]+,[0-9]+$ ]] || return 1
    IFS=, read -r x y <<< "$p"; click_at $((x + 8)) $((y + 6))
}
viewer() {
    ax "click menu button 4 of group 1 of $W" >/dev/null; sleep 0.5
    ax "click menu item \"$1\" of menu 1 of menu button 4 of group 1 of $W" >/dev/null; sleep 2
}
PASS=0; FAIL=0
# Limpa a busca (teclas digitadas em outras janelas podem cair nela enquanto o teste roda).
clear_search() {
    local v; v=$(ax "get value of text field 1 of group 1 of $W")
    [ -n "$v" ] && [ "$v" != "missing value" ] || return 0
    ax "set value of text field 1 of group 1 of $W to \"\"" >/dev/null; sleep 0.3
}
check() { clear_search; if eval "$2"; then echo "PASS $1"; PASS=$((PASS+1)); else echo "FAIL $1"; FAIL=$((FAIL+1)); [ -n "${UI_TEST_DUMP:-}" ] && contents | tr ',' '\n' > "$UI_TEST_DUMP.$FAIL.txt"; fi; }

ax 'set frontmost to true' >/dev/null; sleep 0.5
check "abre com a pasta padrão: 12 faixas + 2 do CUE" 'has "14 faixas"'
viewer "Álbuns";    check "Álbuns: 3 álbuns + Ao Vivo (CUE)" 'has "4 álbuns"'
click_text "Ao Vivo"; check "álbum do CUE: 2 faixas" 'has "2 faixas"'
play_group() {
    for b in $(seq 1 20); do
        P=$(ax "get {position, size} of button $b of group 1 of $W" | tr -d ' ')
        IFS=, read -r bx by bw bh <<< "$P"
        if [ "${bw:-0}" -gt 50 ] && [ "${bw:-0}" -lt 90 ] && [ "${by:-0}" -gt 230 ] && [ "${by:-0}" -lt 320 ] && [ "${bx:-0}" -gt 1300 ]; then click_at $((bx + 20)) $((by + 8)) 2; return; fi
    done
}
play_group;         check "toca o trecho: Parte Um com TOTAL 00:15" 'has "Parte Um" && has "00:15"'
viewer "Álbuns"
click_text "Noites de Vinho"; check "abre álbum: 5 faixas" 'has "5 faixas"'
P=$(ax "get position of button 7 of group 1 of $W" | tr -d ' ')
for b in $(seq 1 20); do
    P=$(ax "get {position, size} of button $b of group 1 of $W" | tr -d ' ')
    IFS=, read -r bx by bw bh <<< "$P"
    if [ "${bw:-0}" -gt 50 ] && [ "${bw:-0}" -lt 90 ] && [ "${by:-0}" -gt 230 ] && [ "${by:-0}" -lt 320 ] && [ "${bx:-0}" -gt 1300 ]; then click_at $((bx + 20)) $((by + 8)) 2; break; fi
done
check "Tocar o álbum toca Abertura do Vinho" 'has "Abertura do Vinho"'
viewer "Gêneros";   check "Gêneros: Sem categoria" 'has "Sem categoria"'
viewer "Playlists"; check "Playlists: Para Dirigir" 'has "Para Dirigir"'
click_text "Para Dirigir"; check "abre playlist: 5 faixas" 'has "5 faixas"'
viewer "Fila";      check "Fila mostra a fila do álbum" 'has "5 faixas"'
# (nomes vindos do disco usam acentos decompostos; por isso uma pasta sem acento)
viewer "Pastas";    check "Pastas: subpasta Noites de Vinho" 'has "Noites de Vinho"'
click_text "Noites de Vinho"; check "entra na subpasta" '[ "$(ax "get name of menu button 2 of group 1 of $W")" = "Biblioteca" ] && has "5 faixas"'
ax 'click menu item "Pasta padrão" of menu 1 of menu bar item "Ir" of menu bar 1' >/dev/null; sleep 1.5
viewer "Músicas"
cp "$(find "$LIB" -name '*Ladeira.flac' | head -1)" "$LIB/Copia Vigiada.flac"
check "vigia de pastas: arquivo novo aparece (15 faixas)" 'has "15 faixas"'
check "app vivo, sem travar" 'pgrep -x Wineup >/dev/null && ax "get name of window 1" >/dev/null'
echo "== $PASS passaram, $FAIL falharam =="
[ "$FAIL" -eq 0 ]
