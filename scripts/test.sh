#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
# Com apenas Command Line Tools, o plugin TestingMacros às vezes falha de forma
# intermitente na primeira compilação após mudanças; uma nova tentativa resolve.
swift test || swift test
