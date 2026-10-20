---
phase: 01-funda-o-e-infraestrutura-de-teste
plan: 01
subsystem: testing
tags: [swiftpm, swift-testing, core]
requires: []
provides:
  - target WineupCore (Foundation puro) com portas e tipos de domínio
  - scripts/test.sh como ponto único de testes
affects: [fases 2-5]
key-files:
  created: [Sources/WineupCore/WineupCore.swift, Sources/WineupCore/Ports.swift, Sources/WineupCore/LibraryRoot.swift, Tests/WineupCoreTests/SmokeTests.swift, scripts/test.sh]
  modified: [Package.swift, .planning/PROJECT.md, 01-CONTEXT.md]
decisions:
  - "Swift Testing funciona com apenas CLT; plano B (runner próprio) não foi necessário"
  - "Sem sandbox; acesso a pastas via LibraryRoot"
requirements-completed: [FND-01, FND-02]
completed: 2026-10-20
---

# Phase 1 Plan 1: WineupCore e infraestrutura de teste

`swift test` roda com Command Line Tools (Swift 6.4, Swift Testing), cobrindo o novo target `WineupCore` (portas AudioEngine/TagIO/LibraryStore/MetadataProvider, Confidence, TagDiff, JournalEntry, LibraryRoot).

## Commits
- 78f48fd: test: target WineupCore e spike de swift test
- f9372bf: feat: contratos do núcleo e LibraryRoot

## Deviations from Plan

1. **[Rule 3 - Blocking] Falha intermitente do plugin TestingMacros.** Após alterar fontes de teste, a primeira compilação às vezes falha com "plugin for module 'TestingMacros' not found"; a segunda passa. Fix: `scripts/test.sh` executa `swift test || swift test`. Verificado: exit 0 após `touch` no teste.
2. **Assinaturas de AudioEngine** alinhadas ao serviço existente: `play(_ url:)` e `setVolume(_ volume:)` (o plano listava `play(url:)`/`setVolume(_ value:)`).
3. `git add .planning` no primeiro commit incluiu todo o `.planning/` (estava não rastreado).
4. `unsafeFlags(["-strict-concurrency=complete"])` funcionou; não precisou do fallback.

## Verification
- `./scripts/test.sh`: 3 testes passam (coreVersionIsSet, confidenceIsOrdered, libraryRootContainsOnlyDescendants, incluindo /Musica vs /Music para T-01-01).
- `swift build -c release` OK; sem imports de SwiftUI/AppKit/SFBAudioEngine no núcleo.

## Known Stubs
None.

## Self-Check: PASSED
