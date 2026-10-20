---
phase: 03-udio-real
plan: 06
subsystem: ui
tags: [swiftui, level-meter, spectrum, eq-presets, replaygain]
requires: ["03-03", "03-05"]
provides: [MeterModel, SpectrumView, presets de EQ persistidos na UI, seletor de ReplayGain]
key-files:
  created: [Sources/Wineup/Model/MeterModel.swift, Sources/Wineup/Components/SpectrumView.swift]
  modified: [Sources/Wineup/Components/LevelMeter.swift, Sources/Wineup/Panels/PlayerPanel.swift, Sources/Wineup/Panels/EqualizerPanel.swift, Sources/Wineup/Model/PlayerState.swift, Sources/Wineup/Library/LibraryController.swift]
requirements-completed: [AUD-01, AUD-04, AUD-05, AUD-07]
completed: 2026-10-20
---

# Phase 3 Plan 6: Painéis ligados ao áudio real Summary

VU e espectro vêm do `LevelTap` (timer de 30 Hz, balística, snapshot velho = silêncio); presets de EQ do usuário e o estado do EQ persistem no banco; ReplayGain (desligado/faixa/álbum) e "evitar clipping" selecionáveis no painel FX.

## Tarefas
1. MeterModel + LevelMeter real + SpectrumView: 4c13a77
2. Presets persistidos, estado do EQ, seletor de ReplayGain: commit "feat(03-06): presets de EQ persistidos..."

## Verificação
`swift build -c release && ./scripts/test.sh && ./scripts/audiocheck.sh && ./scripts/build-app.sh` verde; "Reprodução OK (FLAC, M4A, WAV)". `pkill -x Wineup` executado. Layout mantido; WaveformView segue decorativa (overview real fica para a Fase 5).

## Deviations from Plan
- [Rule 3] O macro `@State` não resolve só com Command Line Tools (plugin SwiftUIMacros ausente); o estado dos diálogos de preset ficou em `PresetDialogs` (ObservableObject via `@StateObject`).
- SpectrumView fica ao lado do LevelMeter na mesma linha (20 barras, largura fixa).
- Presets na UI não tiveram teste automatizado de clique (a persistência é coberta pelos testes do EqPresetStore); smoke do app usou a biblioteca do `build-app.sh`.

## Limitações conhecidas
- AUD-07: a troca real de hardware (fones, AirPods, HDMI) não é automatizável aqui; é coberta pela simulação `wineup-audiocheck configchange` (mudança de formato/taxa do engine). A checagem em hardware real fica pendente para o usuário.
- Faixas Opus (R128) ficam sem ReplayGain (ganho 1,0), pois o SFB 0.14 não as lê.

## Known Stubs
None.

## Self-Check: PASSED
