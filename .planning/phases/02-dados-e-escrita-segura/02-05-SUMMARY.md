---
phase: 02-dados-e-escrita-segura
plan: 05
subsystem: library
tags: [safe-write, backup, journal, undo, clonefile]
requires: [02-01, 02-04]
provides: [TagWriter, BackupStore, FileStat]
affects: [fase 7 (Library Fixer / UI de desfazer)]
key-files:
  created:
    - Sources/WineupLibrary/Tags/BackupStore.swift
    - Sources/WineupLibrary/Tags/FileStat.swift
    - Sources/WineupLibrary/Tags/TagWriter.swift
    - Tests/WineupLibraryTests/TagWriterTests.swift
    - Tests/WineupLibraryTests/TagWriterUndoTests.swift
requirements-completed: [SAFE-01, SAFE-02]
completed: 2026-10-20
---

# Phase 2 Plan 05: Gravador seguro e undo Summary

TagWriter.apply/dryRun/undo: backup por clonefile (fallback de cópia com checagem de espaço), gravação só na cópia de trabalho, verificação total via TagSnapshot, replaceItemAt e journal + snapshots + audio_file + FTS numa única transação.

## Decisions
- Campo vazio ("") em TagChanges significa limpar e equivale a ausente (alinhado ao TagSnapshot).
- Só campos cujo valor realmente muda entram em diffs e na verificação esperada.
- Falhas antes da troca: remove cópia e backup, grava journal 'failed' sem backup_path. Falha de banco após a troca mantém o backup (arquivo já trocado).
- Backups NÃO são apagados automaticamente (open question A3); política de retenção fica para fase futura.
- Undo mantém o backup para auditoria.
- TagWriter NÃO conforma a `TagIO` (assinaturas incompatíveis: dicionário String vs TagChanges/fileID); WineupCore não foi alterado. `journalEntries` mapeia para o `JournalEntry` do WineupCore.

## Deviations from Plan
- [Menor] Critério `grep -c replaceItemAt TagWriter.swift = 1` resulta em 2: um em apply e um em undo (necessário, o plano pede troca atômica nos dois).
- Teste de espaço insuficiente injeta também um clone que falha (ENOTSUP), pois em APFS o clone não consome espaço e a checagem só vale no fallback de cópia.
- Caso `journalEntries` de falhas: entradas 'failed' aparecem com diffs vazios.

## Verification
`swift build -c release && ./scripts/test.sh` passou (48 testes XCTest-style Swift Testing na suíte da biblioteca, 14 novos); nenhum `WineupTests-*` restante em $TMPDIR; único `writeMetadata()` fora de comentários continua só no backend SFB. Testes operam apenas em fixtures dentro de diretório temporário.

## Known Stubs
None.

## Self-Check: PASSED
