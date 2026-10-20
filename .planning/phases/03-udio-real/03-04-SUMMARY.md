---
phase: 03-udio-real
plan: 04
subsystem: audio
tags: [sfbaudioengine, avaudioengine, gapless, replaygain, offline-render]
requires: ["03-01", "03-02"]
provides: [SFBAudioEngineAdapter, ReplayGainReader, wineup-audiocheck]
affects: [03-05, 03-06]
key-files:
  created:
    - Sources/WineupAudio/SFBAudioEngineAdapter.swift
    - Sources/WineupAudio/ReplayGainReader.swift
    - Sources/WineupAudioCheck/main.swift
    - Sources/WineupAudioCheck/Fixtures.swift
    - scripts/audiocheck.sh
    - Tests/WineupAudioTests/ReplayGainReaderTests.swift
  modified: [Package.swift]
key-decisions:
  - "Volume do app em mainMixerNode.outputVolume, nunca player.setVolume"
  - "Cadeia instalada uma vez; reconfigureProcessingGraph religa os tres elos e retorna chain.first"
  - "Gapless por enqueue idempotente (clearQueue + enqueue); tokens ObjectIdentifier(decoder) -> URL"
requirements-completed: [AUD-01, AUD-02, AUD-05, AUD-06, AUD-07]
completed: 2026-10-20
---

# Phase 3 Plan 4: SFBAudioEngineAdapter e wineup-audiocheck Summary

Adaptador SFB da porta AudioEngine (cadeia TimePitch/EQ/balanco, tap no mixer, gapless, ReplayGain somente leitura) provado em release por um executavel de render manual offline.

## Tarefas
1. Adaptador + ReplayGainReader + testes: 9e36357
2. Executavel wineup-audiocheck + scripts/audiocheck.sh: commit "feat(03-04): executavel wineup-audiocheck..."

## Resultados
- `./scripts/audiocheck.sh`: PASS chain, meter, rate, gapless, configchange (44,1 st -> 48 mono -> 96 st -> 44,1 st; 1,5x ~3,0 s e 0,5x ~1,0 s dentro de 5%; A->B->nil->endOfAudio sem corrida de zeros > 16).
- ReplayGainReaderTests: -6,5/0,97/3,25/0,5 lidos, SHA256 do arquivo inalterado.
- Gate `swift build -c release && ./scripts/test.sh && ./scripts/audiocheck.sh` verde (exe `Wineup` continua gerado).

## Deviations from Plan
- [Rule 3] `withEngine` e `throws` (nao `rethrows`): o closure passa por modifyProcessingGraph (@Sendable), entao o erro e capturado em lock e relancado.
- [Rule 3] Target de testes WineupAudioTests ganhou dependencia em SFBAudioEngine (necessaria para gravar tags RG na copia).
- Fixture WAV do teste RG escrita localmente (WAVFixture esta em outro target de testes).
- Tokens de decoders sao liberados quando nowPlaying vira nil (nao a cada troca).

## Limitacoes
- Troca real de dispositivo (fones/AirPods/HDMI) nao e automatizavel; AUD-07 coberto por notificacao simulada.
- Opus R128 nao e lido pelo SFB 0.14 (ganho 1,0).
- audiocheck sem strict concurrency (target executavel de verificacao).

## Known Stubs
None.

## Self-Check: PASSED
