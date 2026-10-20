#!/bin/bash
# Prova o caminho SFB real em release (render manual offline, sem som, só arquivos sintéticos temporários).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --product wineup-audiocheck
.build/release/wineup-audiocheck "${@:-all}"
