---
phase: 03-udio-real
plan: 01
subsystem: audio
tags: [avaudioengine, eq, pan, replaygain, level-meter, swift-testing]
requires: []
provides:
  - EffectChain (TimePitch -> EQ 10 bandas -> mixer de balanço/ganho)
  - LevelTap (RMS/pico + 1024 amostras, snapshot sem bloqueio)
  - Suíte WineupAudioTests com render offline
affects: [03-02, 03-04, 03-05]
tech-stack:
  added: []
  patterns: [render manual offline em AVAudioEngine comum, OSAllocatedUnfairLock.withLockIfAvailable]
key-files:
  created:
    - Sources/WineupAudio/EffectChain.swift
    - Sources/WineupAudio/LevelTap.swift
    - Tests/WineupAudioTests/Support/OfflineRender.swift
    - Tests/WineupAudioTests/EqualizerEffectTests.swift
    - Tests/WineupAudioTests/BalanceTests.swift
    - Tests/WineupAudioTests/EffectChainGainTests.swift
    - Tests/WineupAudioTests/LevelTapTests.swift
  modified: [Package.swift]
key-decisions:
  - "Tap dispara em render manual offline: teste usa o caminho real; process(buffer:) interno cobre a medição direta com buffers sintéticos"
  - "Clamps na camada EffectChain: rate 0,5-2, pan +/-1, ganho 0-8, preamp +/-24, bandas +/-12; não finito vira neutro"
requirements-completed: [AUD-01, AUD-03, AUD-04, AUD-05]
duration: ~20min
completed: 2026-10-20
---

# Phase 3 Plan 1: EffectChain e LevelTap Summary

Cadeia de efeitos TimePitch -> EQ -> balanço e medidor de nível com tap único, provados por render offline sem som (EQ +/-12 dB por banda, preamp, bypass, pan estéreo/mono, ganho linear).

## Tarefas
1. Target WineupAudio + EffectChain + testes de EQ/balanço/ganho: 512f6e5
2. LevelTap + testes: commit seguinte ("feat(03-01): LevelTap ...")

## Resultados
- 10 bandas medidas em +12 e -12 dB (tolerância 0,3), preamp -6, bypass 0 dB, Bass Boost > 5 dB em 40-200 Hz.
- Pan -1/+1 em estéreo e mono: canal oposto < -60 dB, alvo ~ -9,03 dB.
- outputVolume 2,0 = +6 dB; 0,5 = -6 dB; NaN vira 1,0.
- Gate: `swift build -c release && ./scripts/test.sh` verde (suíte completa).

## Deviations from Plan
None - plano executado como escrito. Um aviso de concorrência em LevelTap (captura de var) foi corrigido antes do commit da tarefa 2. Não foi necessário o fallback de `process(buffer:)`, pois o tap dispara em render manual (o teste exige o snapshot); a função interna é usada nos testes de seno/silêncio.

## Known Stubs
None.

## Self-Check: PASSED
