#!/bin/bash
# Ponto de entrada único dos testes (Swift Testing com apenas Command Line Tools).
set -euo pipefail
cd "$(dirname "$0")/.."

# Nas CLT o plugin TestingMacros fica numa subpasta que o compilador nem sempre
# encontra ("plugin for module 'TestingMacros' not found"); passamos o caminho.
PLUGIN_DIR="$(dirname "$(xcrun --find swift)")/../lib/swift/host/plugins/testing"
if [ -d "$PLUGIN_DIR" ]; then
    swift test -Xswiftc -plugin-path -Xswiftc "$PLUGIN_DIR" "$@"
else
    swift test "$@"
fi
