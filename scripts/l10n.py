#!/usr/bin/env python3
"""Traduções do Wineup Player.

Os textos do código (em português) são as chaves. Cada idioma tem um JSON em Localization/<idioma>.json
({chave: tradução}). O compilador extrai as chaves (Text("..."), Button("..."), String(localized:)...).

  l10n.py extract <pasta com .stringsdata>   atualiza Localization/keys.json
  l10n.py check                              mostra o que falta traduzir em cada idioma
  l10n.py todo <idioma>                      lista as chaves que faltam (JSON) para traduzir
  l10n.py build <Contents/Resources>         gera <idioma>.lproj/Localizable.strings no app
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
LOC = ROOT / "Localization"
KEYS = LOC / "keys.json"
SOURCE_LANGUAGE = "pt-BR"
SPECIFIER = re.compile(r"%(?:\d+\$)?[-+ #0]*\d*(?:\.\d+)?(?:hh|h|ll|l|q|z|t|j)?[@dDiuUxXoOfFeEgGcCsSpaA%]")


def specifiers(text):
    """Marcadores de formato sem a posição (%1$@ conta como %@), para comparar original e tradução."""
    return sorted(re.sub(r"\d+\$", "", m) for m in SPECIFIER.findall(text) if m != "%%")


def languages():
    return sorted(p.stem for p in LOC.glob("*.json") if p.stem != "keys")


def load(path, default):
    return json.loads(path.read_text("utf-8")) if path.exists() else default


def extract(folder):
    keys = {}
    for data in sorted(pathlib.Path(folder).rglob("*.stringsdata")):
        doc = json.loads(data.read_text("utf-8"))
        source = doc.get("source", "")
        if "/Sources/" not in source or "/.build" in source:
            continue
        rel = source.split("/Sources/", 1)[1]
        for entry in doc.get("tables", {}).get("Localizable", []):
            key = entry["key"]
            if not key.strip() or not re.search(r"[A-Za-zÀ-ÿ]", key):
                continue
            keys.setdefault(key, f"{rel}:{entry['location']['startingLine']}")
    LOC.mkdir(exist_ok=True)
    KEYS.write_text(json.dumps(dict(sorted(keys.items())), ensure_ascii=False, indent=1) + "\n", "utf-8")
    print(f"{len(keys)} chaves em {KEYS.relative_to(ROOT)}")


def check():
    keys = load(KEYS, {})
    ok = True
    for lang in languages():
        table = load(LOC / f"{lang}.json", {})
        missing = [k for k in keys if k not in table]
        bad = [k for k, v in table.items() if k in keys and specifiers(k) != specifiers(v)]
        print(f"{lang}: {len(keys) - len(missing)}/{len(keys)} traduzidas, {len(bad)} com marcadores (%@, %lld) diferentes")
        for k in bad[:5]:
            print(f"   marcadores: {k!r} -> {table[k]!r}")
        ok = ok and not missing and not bad
    return 0 if ok else 1


def todo(lang):
    keys = load(KEYS, {})
    table = load(LOC / f"{lang}.json", {})
    print(json.dumps([k for k in keys if k not in table], ensure_ascii=False, indent=1))


def escape(text):
    return text.replace("\\", "\\\\").replace('"', '\\"').replace("\n", "\\n").replace("\t", "\\t")


def build(resources):
    resources = pathlib.Path(resources)
    keys = load(KEYS, {})
    for lang in languages():
        table = load(LOC / f"{lang}.json", {})
        lines = [f'"{escape(k)}" = "{escape(table[k])}";' for k in keys if k in table and table[k]]
        folder = resources / f"{lang}.lproj"
        folder.mkdir(parents=True, exist_ok=True)
        (folder / "Localizable.strings").write_text("\n".join(lines) + "\n", "utf-16")
    # Português é o texto do código, mas a tabela precisa existir: sem ela o macOS cai no idioma
    # reserva (inglês) mesmo com o app em português.
    folder = resources / f"{SOURCE_LANGUAGE}.lproj"
    folder.mkdir(parents=True, exist_ok=True)
    lines = [f'"{escape(k)}" = "{escape(k)}";' for k in keys]
    (folder / "Localizable.strings").write_text("\n".join(lines) + "\n", "utf-16")
    print(f"{len(languages())} idiomas gerados em {resources}")


if __name__ == "__main__":
    command = sys.argv[1] if len(sys.argv) > 1 else ""
    if command == "extract" and len(sys.argv) == 3:
        extract(sys.argv[2])
    elif command == "check":
        sys.exit(check())
    elif command == "todo" and len(sys.argv) == 3:
        todo(sys.argv[2])
    elif command == "build" and len(sys.argv) == 3:
        build(sys.argv[2])
    else:
        print(__doc__)
        sys.exit(2)
