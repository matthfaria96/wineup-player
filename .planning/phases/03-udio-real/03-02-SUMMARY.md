---
phase: 03-udio-real
plan: 02
subsystem: audio
tags: [replaygain, eq, fft, accelerate, swift-testing]
requires: []
provides:
  - RateMapping, ReplayGainMath, EqMath, NextTrackPlanner, MeterMath/SpectrumAnalyzer (WineupCore, sem UI)
  - Porta AudioEngine ampliada
affects: [03-04, 03-05]
key-files:
  created:
    - Sources/WineupCore/Audio/RateMapping.swift
    - Sources/WineupCore/Audio/ReplayGainMath.swift
    - Sources/WineupCore/Audio/EqMath.swift
    - Sources/WineupCore/Audio/MeterMath.swift
    - Sources/WineupCore/Audio/NextTrackPlanner.swift
  modified: [Sources/WineupCore/Ports.swift]
key-decisions:
  - "EqMath: resposta gaussiana por banda com sigma 0,7 oitava (nas 10 frequências do app) dá pico ~+20 dB com tudo em +12; compensação na grade, sem limitador"
  - "SpectrumAnalyzer arredonda size para potência de 2 e trata entradas de tamanho/valores inválidos (T-03-05)"
requirements-completed: [AUD-01, AUD-02, AUD-04, AUD-05, AUD-06]
completed: 2026-10-20
---

# Phase 3 Plan 2: Matemática pura de áudio Summary

Taxa log 0,5x-2x, ReplayGain linear defensivo (NaN/Inf, +/-30 dB, 1/pico), compensação de EQ por grade, planejador de próxima faixa e espectro FFT/balística, todos puros em WineupCore, mais a porta `AudioEngine` ampliada.

## Tarefas
1. RateMapping, ReplayGainMath, EqMath, NextTrackPlanner + porta: 7cd9923
2. MeterMath (SpectrumAnalyzer, dbToMeter, isStale, ballistic): df7b4e1

## Verificação
`swift build -c release && ./scripts/test.sh` verde (WineupCore 34 testes, Library 59, Audio 15). Sem UI em WineupCore.

## Deviations from Plan
- Os testes foram escritos junto da implementação em cada tarefa (um commit por tarefa, sem commits separados RED/GREEN).
- O mapeamento do EQ usa sigma 0,7 oitava (não a fórmula literal com bw/2) para cumprir o requisito de pico >= 19 dB; a fórmula literal daria ~15,5 dB.
- `NextTrackPlanner` implementado direto (sem reusar `TrackList.neighbor`, que faz wrap).

## Known Stubs
None.

## Self-Check: PASSED
