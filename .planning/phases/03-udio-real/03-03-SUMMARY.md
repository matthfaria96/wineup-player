---
phase: 03-udio-real
plan: 03
subsystem: audio
tags: [eq, presets, grdb, app_setting]
requires: []
provides:
  - EqPreset (validação + embutidos) em WineupCore
  - EqPresetStore/EqState em WineupLibrary (chaves eq.presets.v1, eq.current.v1)
affects: [03-05]
key-files:
  created:
    - Sources/WineupCore/Audio/EqPreset.swift
    - Sources/WineupLibrary/Settings/EqPresetStore.swift
requirements-completed: [AUD-04]
completed: 2026-10-20
---

# Phase 3 Plan 3: Presets de EQ persistidos Summary

Presets do usuário (salvar, renomear, apagar) e estado atual do EQ persistem em `app_setting` como JSON versionado, com decodificação tolerante, validação, limite de 200 e fallback para os embutidos.

## Tarefas
1. EqPreset (tipo, validação, embutidos): 23c43fd
2. EqPresetStore + testes de persistência/corrupção: commit "feat(03-03): EqPresetStore ..."

## Verificação
`swift build -c release && ./scripts/test.sh` verde (59 testes na biblioteca).

## Deviations from Plan
- O preset selecionado é guardado como `presetName` dentro de `EqState` (`eq.current.v1`), em vez de uma chave `eq.selected.v1` separada.
- Duplicidade de nome é case-insensitive; presets com nome embutido ou repetido no JSON são descartados na leitura.
- Testes escritos junto da implementação (sem commits RED/GREEN separados).

## Known Stubs
None.

## Self-Check: PASSED
