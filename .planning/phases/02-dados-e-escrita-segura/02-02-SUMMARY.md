---
phase: 02-dados-e-escrita-segura
plan: 02
subsystem: scanner
tags: [fts, grdb, sfbaudioengine, incremental-scan]
requires: [02-01]
provides: [TagReader, FileEnumerator, Scanner, ScanProgress]
affects: [02-03, 02-04, 02-05, 02-06]
key-files:
  created:
    - Sources/WineupLibrary/Scanner/TagReader.swift
    - Sources/WineupLibrary/Scanner/FileEnumerator.swift
    - Sources/WineupLibrary/Scanner/Scanner.swift
    - Tests/WineupLibraryTests/ScannerTests.swift
    - Tests/WineupLibraryTests/MissingFilesTests.swift
    - Tests/WineupLibraryTests/ScanScaleTests.swift
key-decisions:
  - "Movido = exatamente 1 registro sumido e 1 candidato novo com mesmo (inode,size); ambiguo vira arquivo novo"
  - "Erro de leitura grava read_error generico ('unreadable'), sem caminho"
metrics:
  completed: 2026-10-20
requirements-completed: [LIB-02, LIB-03, LIB-07]
---

# Phase 2 Plan 02: Scanner incremental Summary

Varredura incremental em duas etapas (enumeracao fts por stat, depois tags so de novos/alterados em lotes transacionais), com progresso, cancelamento, deteccao de movidos preservando id e ausentes sem DELETE.

## Commits
- a5847fd: TagReader e FileEnumerator
- (git log): Scanner e testes de movidos/ausentes
- (git log): teste de escala 10k

## Resultados
- 2a varredura sem mudancas: read=0; alterar 1 arquivo: read=1.
- Cancelamento apos o 1o lote deixa banco consistente; nova varredura completa o restante.
- Raiz inacessivel: online=0, nenhum arquivo marcado missing.
- 10 mil arquivos vazios: enumeracao < 3 s, scan completo ~4 s no total do teste, maior atraso da main < 250 ms, 2a varredura toRead=0.
- Gate `swift build -c release && ./scripts/test.sh` passa (19 testes da biblioteca + 9 do core); nenhum WineupTests-* sobra em $TMPDIR.

## Deviations from Plan
1. [Rule 1] `trackNumber`/`discNumber` do SFB chegam como `Int` no Swift (nao NSNumber); removido `.intValue`.
2. Pastas ocultas (nome iniciando em ".") tambem sao puladas na enumeracao, alem dos arquivos ocultos.
3. Movido que estava `missing` e relido (para voltar ao indice FTS) mantendo o mesmo id.
4. Testes escritos junto da implementacao (sem commits RED separados).
5. Teste de cancelamento cancela a propria Task dentro do callback de progresso (`withUnsafeCurrentTask`), evitando corrida.

## Known Stubs
Nenhum.

## Self-Check: PASSED
