---
phase: 02-dados-e-escrita-segura
plan: 04
subsystem: tags
tags: [taglib, sfbaudioengine, id3, flac, m4a, ogg, wav]
requires: [02-01]
provides:
  - TagChanges, TagSnapshot, TagBackend/TagBackends.backend(for:)
  - SFBTagBackend (FLAC/M4A/ALAC/Opus/Vorbis), ID3TagBackend (MP3/WAV via wid3_write)
  - Fixtures e TagProbe para testes de preservação
affects: [02-05]
key-files:
  created:
    - Sources/WineupLibrary/Tags/*.swift
    - Tests/WineupLibraryTests/Support/Fixtures.swift
    - Tests/WineupLibraryTests/Support/TagProbe.swift
    - Tests/WineupLibraryTests/TagPreservationTests.swift
  modified: [Sources/WineupID3/WineupID3.mm, Sources/WineupID3/include/WineupID3.h]
key-decisions:
  - "Ano sempre gravado como TDRC com texto cru; o TagLib rebaixa para TYER em ID3v2.3 ao salvar"
  - "WAV: salva só ID3v2 (StripNone), nunca toca no LIST/INFO"
requirements-completed: [SAFE-03]
metrics:
  completed: 2026-10-20
---

# Phase 2 Plan 04: Backends de escrita de tags Summary

Backends por formato (SFB para FLAC/M4A/ALAC/Opus/Vorbis, shim TagLib para MP3/WAV) com round-trip provando preservação de campos desconhecidos, capas, versão ID3, data parcial e INFO do WAV.

## Commits
- Tarefa 1: fixtures e sonda crua (`test(02-04)`)
- Tarefa 2: backends, snapshot, shim e `TagPreservationTests` (`feat(02-04)`)

## Resultado
`swift build -c release && ./scripts/test.sh`: 34 testes da biblioteca + 9 do core passam. `TagPreservationTests` cobre FLAC, M4A AAC, ALAC, Opus, Vorbis, MP3 v2.3, MP3 v2.4, WAV e WAV com INFO. Nenhum arquivo de áudio commitado (fixtures geradas em `withTempDir`).

## Deviations from Plan
1. [Rule 1 - Bug] `TagSnapshot` trata string vazia como campo ausente: o SFB devolve "" para campos que o TagLib cria vazios (WAV recém-etiquetado, M4A), o que gerava diferenças falsas.
2. [Rule 1 - Bug] O ano usa sempre o frame TDRC no shim em vez de escolher TYER/TDRC na mão: o TagLib converte TYER em TDRC na leitura e rebaixa para TYER ao salvar em v2.3. O teste confirma TYER="2021" em v2.3 e TDRC em v2.4, sem o frame da outra versão.
3. Track/disco preservam o sufixo "/total" já existente em TRCK/TPOS (acréscimo para não perder dado).
4. Testes e implementação foram commitados juntos na tarefa 2 (sem commit RED separado); o ponto de partida `Shim.mm` do scratchpad não existia mais, o shim foi escrito a partir de `WineupID3.mm`.

## Limitações documentadas
- M4A: o SFB não expõe átomos freeform arbitrários (`----`) em `additionalMetadata`; a preservação é verificada por bytes (`com.test`, `CUSTOM`, `keepme` continuam no arquivo). O tipo da capa (frente/verso) não existe em `covr`, então só número e bytes são comparados.
- Sem ID3v2 prévio: MP3 recebe v2.3 e WAV recebe v2.4 (convenção do shim).
- O `stco` da fixture M4A com átomo inserido à mão pode ficar inconsistente; o teste só relê tags.

## Known Stubs
Nenhum.

## Threat Flags
Nenhum. Mitigações T-02-14/15/16 aplicadas (try/catch(...) no shim, StripNone + versão original, withCString com escopo). T-02-13 depende do TagWriter (02-05) chamar os backends só na cópia de trabalho.

## Self-Check: PASSED
