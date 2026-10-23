#!/bin/bash
# Atualiza a seção "Versões exatas" de Resources/THIRD_PARTY_NOTICES.md a partir do Package.resolved.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - <<'PY'
import json, re
pins = json.load(open("Package.resolved"))["pins"]
rows = "\n".join(f"| {p['identity']} | {p['state'].get('version') or p['state'].get('revision','')[:12]} | {p['location']} |"
                 for p in sorted(pins, key=lambda p: p["identity"]))
section = ("<!-- versoes:inicio -->\n## Versões exatas (geradas do Package.resolved a cada build)\n\n"
           "| Pacote | Versão | Origem |\n|---|---|---|\n" + rows + "\n<!-- versoes:fim -->")
path = "Resources/THIRD_PARTY_NOTICES.md"
text = open(path).read()
if "<!-- versoes:inicio -->" in text:
    text = re.sub(r"<!-- versoes:inicio -->.*?<!-- versoes:fim -->", lambda _: section, text, flags=re.S)
else:
    text = text.rstrip() + "\n\n" + section + "\n"
open(path, "w").write(text)
PY
