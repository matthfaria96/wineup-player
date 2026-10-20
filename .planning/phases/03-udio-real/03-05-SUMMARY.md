---
phase: 03-udio-real
plan: 05
subsystem: audio
tags: [swift, sfbaudioengine, gapless, replaygain]
requires: [03-04]
provides: [PlayerState sobre SFBAudioEngineAdapter, meter exposto]
key-files:
  modified: [Package.swift, Sources/Wineup/Model/PlayerState.swift]
  deleted: [Sources/Wineup/Audio/AudioEngineService.swift]
metrics:
  completed: 2026-10-20
---

# Phase 03 Plan 05: Migração para o adaptador Summary

App agora toca pelo SFBAudioEngineAdapter com velocidade (0,5x-2x), balanço, volume do app, ReplayGain, gapless por fila e troca de dispositivo.

## Commits
- 91ff592: feat(03-05) tarefas 1 e 2 (mesmo arquivo, um commit único)

## Deviations from Plan
- Tarefas 1 e 2 commitadas juntas, pois ambas alteram só PlayerState.swift. Em nowPlayingChanged, duplicatas de URL preferem a próxima ocorrência após a faixa atual.

## Verification
swift build -c release, test.sh, audiocheck.sh e build-app.sh passaram ("Reprodução OK (FLAC, M4A, WAV)"). pkill -x Wineup executado.

## Self-Check: PASSED
