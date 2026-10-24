#!/bin/bash
# Extrai do código todos os textos traduzíveis (o compilador gera os .stringsdata) para Localization/keys.json.
set -euo pipefail
cd "$(dirname "$0")/.."
OUT="$(mktemp -d)"
trap 'rm -rf "$OUT"' EXIT
swift build --scratch-path .build-l10n --product Wineup \
    -Xswiftc -emit-localized-strings -Xswiftc -emit-localized-strings-path -Xswiftc "$OUT" >/dev/null
python3 scripts/l10n.py extract "$OUT"
python3 scripts/l10n.py check || true
