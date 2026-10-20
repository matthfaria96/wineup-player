---
phase: 01-funda-o-e-infraestrutura-de-teste
verified: 2026-10-20T00:00:00Z
status: passed
score: 4/4 must-haves verified
---

# Phase 1 Verification

Goal: núcleo testável separado da UI; prova cedo de teste e empacotamento só com Command Line Tools.

| # | Truth | Status | Evidence |
|---|-------|--------|----------|
| 1 | Targets SwiftPM; WineupCore sem UI; app toca FLAC/M4A/WAV | VERIFIED | Package.swift tem Wineup, WineupCore, WineupCoreTests. WineupCore importa só Foundation. App importa WineupCore em 8+ arquivos. `swift build -c release` completou. Reprodução OK informada pelo orquestrador. |
| 2 | `swift test` roda com CLT | VERIFIED | `./scripts/test.sh` rodou 9 testes, todos passaram. |
| 3 | IDs estáveis sob reordenar/filtrar | VERIFIED | Teste `reorderFilterSortKeepIDs` e `removingKeepsOtherIDs` passam. Model/Track.swift e PlayerState usam WineupCore. |
| 4 | .app assinado abre fora do build, com rpath e frameworks | VERIFIED | `verify-app.sh` retornou "Empacotamento OK". Ele checa rpath, frameworks embutidos, codesign e execução a partir de um diretório temporário. |

Requisitos: FND-01 (truth 1), FND-02 (2), FND-03 (3), FND-04 (4). Todos satisfeitos. Nenhum órfão: os 4 IDs aparecem nos frontmatters dos PLANs.

Anti-padrões: nenhum bloqueador. Aviso menor do linker sobre um search path inexistente das CLT (inofensivo).

Itens humanos: nenhum (modo autônomo; reprodução já coberta por smoke automatizado).
