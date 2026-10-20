# Phase 3: Áudio Real - Context

**Gathered:** 2026-10-20
**Status:** Ready for planning
**Mode:** Auto-generated (discuss skipped via workflow.skip_discuss)

<domain>
## Phase Boundary

O que o usuário vê e ouve reflete o áudio de verdade: medidores (VU + espectro), velocidade, balanço, equalizador verificável com presets, ReplayGain não destrutivo, gapless e troca de dispositivo de saída. Requisitos: AUD-01..07.

</domain>

<decisions>
## Implementation Decisions

- Novo target `WineupAudio` (depende de WineupCore e SFBAudioEngine) com `SFBAudioEngineAdapter` implementando a porta `AudioEngine` do WineupCore; o app passa a usá-lo no lugar de `Sources/Wineup/Audio/AudioEngineService.swift` (migrar sem regressão).
- Restrição dura do SFBAudioEngine 0.14: o grafo só pode ser alterado entre `sourceNode` e `mainMixerNode` via `modifyProcessingGraph`; a cadeia inteira (ordem decidida pela pesquisa, ex.: TimePitch → EQ → mixer de balanço) é religada em `audioPlayer(_:reconfigureProcessingGraph:with:)`. Qualquer tap/nó que viole isso aborta o app — a pesquisa deve provar onde instalar o tap de medição.
- Medição: tap só copia/calcula RMS/pico para buffer circular pré-alocado, sem alocação/lock na thread de áudio; FFT (Accelerate/vDSP) fora do tap; UI recebe snapshots a 30–60 Hz.
- Velocidade: `AVAudioUnitTimePitch` (rate 0.5–2.0, pitch preservado); relógio/progresso/letras corrigidos pelo fator de taxa.
- Balanço: pan de um nó dentro do trecho permitido (pesquisa decide; testar mono).
- EQ: manter AVAudioUnitEQ 10 bandas + preamp; presets do usuário persistidos (no banco `app_setting` da Fase 2 ou arquivo de perfil — preparar para PROF-01 da Fase 4). Verificação objetiva do efeito via render offline (`enableManualRenderingMode`) num `AVAudioEngine` de teste com o mesmo EQ.
- ReplayGain: ganho aplicado num nó (track/album via metadados da SFB), nunca regrava áudio; com proteção contra clipping (peak).
- Gapless: pré-enfileirar a próxima faixa com `enqueue` da SFB em vez de `play(next)` no fim.
- Troca de dispositivo: tratar `audioEngineConfigurationChange` sem travar.
- UI da fase: ligar os painéis existentes (LevelMeter, espectro/forma de onda, sliders de velocidade/balanço, FX) aos dados reais, sem redesenhar layout (redesign é Fase 5).
- Gate de cada plano: `swift build -c release && ./scripts/test.sh`; fim da fase: `./scripts/build-app.sh` (smoke de reprodução). Smoke/testes nunca usam a biblioteca real do usuário (WINEUP_LIBRARY_PATH temporário).

### Claude's Discretion
Demais escolhas a critério do pesquisador/planejador.

</decisions>

<code_context>
## Existing Code Insights

- `Sources/Wineup/Audio/AudioEngineService.swift`: SFB AudioPlayer + AVAudioUnitEQ inserido entre sourceNode e mainMixerNode (`insertEqualizer` + delegate `reconfigureProcessingGraph`), callbacks de fim/erro para main.
- `WineupCore` tem a porta `AudioEngine` (`play(_ url:)`, `setVolume(_ volume:)`...).
- `Sources/Wineup/Components/LevelMeter.swift` e `WaveformView.swift` hoje são simulados; `PlayerPanel` tem sliders de velocidade/balanço sem efeito.

</code_context>

<specifics>
## Specific Ideas

Itens [VERIFICAR] 3–7 do `.planning/research/SUMMARY.md`; armadilhas 3, 4, 5, 15, 16 do PITFALLS.md.

</specifics>

<deferred>
## Deferred Ideas

Visualizações avançadas (MilkDrop) ficam em v2.

</deferred>
