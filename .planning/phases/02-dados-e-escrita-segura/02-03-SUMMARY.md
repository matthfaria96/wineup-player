---
phase: 02-dados-e-escrita-segura
plan: 03
subsystem: search
tags: [fts5, grdb, browse]
requires: [02-01]
provides: [SearchService, BrowseService, LibraryTrack]
affects: [02-04, 02-05, 02-06]
key-files:
  created:
    - Sources/WineupLibrary/Search/LibraryTrack.swift
    - Sources/WineupLibrary/Search/SearchService.swift
    - Sources/WineupLibrary/Search/BrowseService.swift
    - Tests/WineupLibraryTests/Support/SyntheticLibrary.swift
    - Tests/WineupLibraryTests/SearchTests.swift
    - Tests/WineupLibraryTests/BrowseTests.swift
    - Tests/WineupLibraryTests/SearchScaleTests.swift
key-decisions:
  - "Singles = consulta virtual (album nulo/Unknown Album OU release com 1 faixa presente); id -1; nada gravado"
  - "Genero nulo/vazio = 'Sem categoria' via COALESCE(NULLIF(genre,''), ?) com argumento vinculado"
  - "Pastas agrupadas em SQL pelo diretorio pai (rtrim(path, replace(path,'/','')))"
metrics:
  completed: 2026-10-20
requirements-completed: [LIB-04, LIB-05, LIB-07]
---

# Phase 2 Plan 03: Busca e navegacao Summary

Busca FTS5 sem acento com entrada sanitizada (tokens entre aspas + prefixo, MATCH vinculado, status present) e navegacao por artista/album/genero/pasta/todas, com album virtual Singles e genero "Sem categoria", provadas com 100 mil faixas sinteticas.

## Commits
- 6cbc3ef: SearchService, BrowseService, LibraryTrack, testes
- 3bd70c3: teste de escala 100k

## Resultados
- "beyonce" acha "Beyoncé", "ros" acha album "Rós", "hal" acha "Halo"; entradas hostis (`"`, `a* -b`, AND, OR, NEAR, `(x`, `title:x`, SQL) nunca lancam; vazio devolve [].
- Itens missing fora da busca; navegacao tem `includeMissing` (padrao false).
- Singles nao cria release nem release_track (contagens iguais antes/depois).
- 100k: insercao + todos os testes de escala em ~24 s; busca (beyonce, art, album 42) < 100 ms na mediana, artists() e allTracks(offset 50k) < 200 ms, atraso maximo da main < 150 ms.
- Gate `swift build -c release && ./scripts/test.sh` passa (25 testes da biblioteca + 9 do core); nenhum WineupTests-* sobra em $TMPDIR.

## Deviations from Plan
1. Testes escritos junto da implementacao (sem commits RED separados).
2. `SyntheticLibrary.insert` e async (usa `pool.write`) e devolve o id da raiz; foram adicionados `addTrack`/`addRoot` para testes pequenos.
3. Sem ordenacao adicional por relevancia alem de `rank`.

## Known Stubs
Nenhum.

## Self-Check: PASSED
