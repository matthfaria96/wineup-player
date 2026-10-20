---
phase: 02-dados-e-escrita-segura
plan: 01
subsystem: database
tags: [grdb, sqlite, fts5, taglib, swiftpm]
requires: []
provides:
  - Package.swift final da fase (targets WineupLibrary, WineupID3, WineupLibraryTests)
  - migration v1 (LIB-06), Records, LibraryDatabase, LibraryRootStore, CatalogWriter
affects: [02-02, 02-03, 02-04, 02-05, 02-06]
tech-stack:
  added: [GRDB.swift 7.11.1, CXXTagLib 2.3.2 (direto)]
  patterns: [FKs RESTRICT, FTS5 com conteúdo próprio rowid=audio_file.id]
key-files:
  created:
    - Sources/WineupLibrary/Database/*.swift
    - Sources/WineupID3/WineupID3.mm
    - Sources/WineupID3/include/WineupID3.h
    - Tests/WineupLibraryTests/*
  modified: [Package.swift, Package.resolved, scripts/test.sh, Resources/THIRD_PARTY_NOTICES.md]
key-decisions:
  - "track_mark.color usa os 6 rawValues reais de MarkColor (sem gray)"
metrics:
  completed: 2026-10-20
requirements-completed: [LIB-01, LIB-06]
---

# Phase 2 Plan 01: Fundação de dados Summary

Esquema SQLite v1 com GRDB (16 tabelas + FTS5), raízes persistentes e ingestão idempotente de catálogo, com shim TagLib mínimo (WineupID3) e Package.swift final da fase.

## Commits
- 6d00c8e: dependências, shim WineupID3, test.sh com "$@", utilitários de teste
- 85765cd: migration v1 e Records
- (Tarefa 3): LibraryRootStore e CatalogWriter (ver git log)

## Deviations from Plan

1. [Rule 1 - Bug] `belongsTo("root")` do GRDB gera coluna `rootId`; trocado por colunas explícitas `*_id` com `.references(..., onDelete: .restrict)`.
2. [Rule 1] `track_mark.color`: o plano citava `gray`, mas `MarkColor` tem só green, blue, purple, red, orange, yellow; o CHECK usa esses 6 (instrução do plano: mesmos rawValues).
3. [Rule 3] `config.foreignKeysEnabled = true` explícito (padrão do GRDB, mantido por clareza).
4. Testes escritos junto da implementação em um único commit por tarefa (sem commits RED separados).
5. `LibraryRootStore` ganhou `init(db:)` público; `ArtistRecord`/etc. têm inicializadores públicos.

## Known Stubs
Nenhum.

## Verification
`swift build -c release` e `./scripts/test.sh` passam (9 testes da biblioteca + 9 do core).

## Self-Check: PASSED
