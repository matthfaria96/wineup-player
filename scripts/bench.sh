#!/bin/bash
# Mede o app com uma biblioteca sintética grande (padrão 20 mil faixas), sem tocar na sua biblioteca.
# Uso: ./scripts/bench.sh [N]   (precisa do app em build/ e de permissão de Acessibilidade)
set -euo pipefail
cd "$(dirname "$0")/.."
N="${1:-20000}"
APP="$(pwd)/build/Wineup Player.app"
TMP="$(mktemp -d)"
trap 'pkill -f "$TMP" 2>/dev/null || true; pkill -x Wineup 2>/dev/null || true; rm -rf "$TMP"' EXIT
DB="$TMP/library.sqlite"; ROOT="$TMP/Biblioteca"; LOG="$TMP/perf.log"
mkdir -p "$ROOT"
"$(swift build -c release --show-bin-path)/wineup-demo" --synthetic "$N" "$DB" "$ROOT" >/dev/null

pkill -x Wineup 2>/dev/null || true; sleep 1
open -n --env WINEUP_LIBRARY_PATH="$DB" --env WINEUP_DEFAULT_FOLDER="$ROOT" \
     --env WINEUP_NO_SCAN=1 --env WINEUP_PERF_LOG="$LOG" "$APP"
for _ in $(seq 1 60); do [ -s "$LOG" ] && break; sleep 0.5; done
sleep 2

ax() { osascript -e "tell application \"System Events\" to tell process \"Wineup\" to $1" 2>/dev/null; }
view() {
    ax "click menu button 4 of group 1 of window \"Wineup Player\"" >/dev/null
    sleep 0.4
    ax "click menu item \"$1\" of menu 1 of menu button 4 of group 1 of window \"Wineup Player\"" >/dev/null
    sleep 4
}
ax 'set frontmost to true' >/dev/null
for v in "Álbuns" "Artistas" "Gêneros" "Músicas"; do view "$v"; done

# Seleção: cliques reais em 6 linhas da lista de Músicas.
P=$(ax 'get position of scroll area 1 of group 1 of window "Wineup Player"' | tr -d ' ')
IFS=, read SX SY <<< "$P"
for k in 1 2 3 4 5 6; do ./scripts/tools/click $((SX + 120)) $((SY + 15 + k * 29)); sleep 0.7; done

# Resposta da interface: tempo de ida e volta da acessibilidade (espera a thread principal).
t0=$(python3 -c 'import time;print(time.time())')
for _ in 1 2 3 4 5; do ax 'get name of window 1' >/dev/null; done
t1=$(python3 -c 'import time;print(time.time())')

echo "== $N faixas =="
cat "$LOG"
python3 -c "print('resposta da janela (média de 5): %.0f ms' % (($t1-$t0)/5*1000))"
echo "memória: $(ps -o rss= -p "$(pgrep -x Wineup)" | awk '{printf "%.0f MB", $1/1024}')"
