# Fase 3: Áudio Real - Pesquisa

**Pesquisado em:** 2026-10-20
**Domínio:** SFBAudioEngine 0.14.0 sobre AVAudioEngine (grafo de efeitos, medição, gapless, ReplayGain, troca de dispositivo) em Swift/SwiftUI, macOS 14+, só Command Line Tools
**Confiança geral:** ALTA (as questões de risco foram resolvidas lendo o fonte do SFB 0.14.0 e rodando experimentos reais; os pontos que dependem de hardware real estão marcados)

## Resumo

Todas as sete perguntas de risco foram respondidas com evidência. Em síntese: (1) `modifyProcessingGraph` só verifica, depois do bloco, que a entrada do `outputNode` continua sendo o `mainMixerNode`; `installTap` em `mainMixerNode` ou em nós inseridos não altera conexões, não aborta e o tap sobrevive a `reconfigureProcessingGraph` e à notificação de mudança de configuração. (2) A cadeia `sourceNode → TimePitch → EQ → mixer de balanço → mainMixerNode` funciona, inclusive com troca 44,1 kHz estéreo → 48 kHz mono → 96 kHz estéreo; o delegate deve religar todos os elos internos e **retornar o primeiro nó da cadeia** (o SFB conecta `sourceNode` a ele). (3) O `currentTime`/`totalTime` do SFB **já está no domínio do conteúdo** (posição do arquivo): a 1,5x, 2 s de relógio de parede deram `currentTime` = 2,96 s. A hipótese do PITFALLS ("não considera a taxa") está refutada: progresso e letras não precisam de correção; só o tempo restante em parede (`(total - atual) / taxa`) precisa.

Gapless com a cadeia inserida funciona para faixas de mesmo formato (sem corrida de silêncio > 16 frames medida na saída); junção com taxa diferente reconfigura o grafo e deixa um buraco (≈93 ms medido), inevitável no SFB. O sinal de troca de faixa é `nowPlayingChanged` (junto com `renderingStarted`); o fim da fila vem como `nowPlayingChanged(nil)` seguido de `audioPlayerEndOfAudio`. ReplayGain é lido por `AudioFile(readingPropertiesAndMetadataFrom:)` (`replayGainTrackGain` em dB, `...Peak` linear) e pode ser aplicado como ganho linear em `AVAudioMixerNode.outputVolume`, que aceita valores acima de 1 (medido: 2.0 = +6,02 dB). O efeito do EQ é verificável de forma objetiva com `AVAudioEngine` em modo de render manual (+12 dB exatos no centro de cada banda; preamp -6 = -6,00 dB).

Dois achados novos que mudam o desenho: (a) o assert de host time do SFB (`AudioPlayer.mm:226`) **aborta o processo em build debug** quando o `AudioPlayer` é renderizado em modo manual, então testes `swift test` (debug) não podem dirigir o player do SFB offline; em release os asserts do SFB estão compilados fora e a renderização offline funciona. (b) `AudioPlayer.setVolume` do SFB muda o volume do **dispositivo de saída** (HAL, `kHALOutputParam_Volume`), não o do app; o volume do app deve ir em `mainMixerNode.outputVolume`.

**Recomendação principal:** criar `EffectChain` (nós TimePitch, EQ, mixer de balanço/ganho) como classe independente do SFB, testável com um `AVAudioEngine` comum em `swift test`; o `SFBAudioEngineAdapter` só a instala em `modifyProcessingGraph`, mede com um único tap em `mainMixerNode`, e um executável de verificação em release (`wineup-audiocheck`) cobre o caminho real SFB com render offline.

## Mapa de Responsabilidade Arquitetural

| Capacidade | Camada principal | Camada secundária | Justificativa |
|------------|------------------|-------------------|---------------|
| Decodificação, fila, gapless, relógio | WineupAudio (SFB `AudioPlayer`) | — | O SFB possui decoders, ring buffer e eventos |
| Cadeia de efeitos (velocidade, EQ, balanço, ganho RG) | WineupAudio (`EffectChain` sobre AVAudioEngine) | — | Só pode viver entre `sourceNode` e `mainMixerNode` |
| Medição (RMS/pico + amostras) | WineupAudio (tap em `mainMixerNode`) | — | Um ponto fixo, formato estável |
| FFT e balística do espectro | Apresentação (fora do tap; função pura em WineupCore) | UI (SwiftUI Canvas) | Evita custo na thread de áudio; testável sem áudio |
| Matemática (taxa↔slider, pan↔slider, ganho RG, preamp automático) | WineupCore (puro) | — | Testável sem hardware |
| Presets do EQ | WineupCore (modelo/codec) + WineupLibrary (`app_setting`) | PROF-01 (Fase 4) | Tabela `app_setting` já existe; preparar migração para perfil |
| Leitura de ReplayGain | WineupAudio (`AudioFile` fora da main) | — | Somente leitura; não grava tags |
| Estado de UI (play, progresso, faixa atual) | App (`PlayerState`, main) | — | Delegate do SFB chama fora da main; hop para main |

<user_constraints>
## Restrições do Usuário (do CONTEXT.md)

### Decisões travadas
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

### Critério do Claude (discricionário)
Demais escolhas a critério do pesquisador/planejador.

### Ideias adiadas (FORA DE ESCOPO)
Visualizações avançadas (MilkDrop) ficam em v2.
</user_constraints>

<phase_requirements>
## Requisitos da Fase

| ID | Descrição | Suporte da pesquisa |
|----|-----------|---------------------|
| AUD-01 | Espectro e VU refletem o áudio que toca | Tap único em `mainMixerNode` (provado legal e persistente); cálculo RMS/pico no tap, FFT fora; tratar "dados velhos" como silêncio (engine parado não entrega buffers) |
| AUD-02 | Velocidade com tempo/letras sincronizados | `AVAudioUnitTimePitch.rate`; SFB `currentTime` já é tempo de conteúdo (medido); só o restante em parede divide pela taxa |
| AUD-03 | Balanço esquerda/direita | `AVAudioMixerNode.pan` no mixer de balanço antes do `mainMixerNode`; medido com estéreo, mono e só-esquerda |
| AUD-04 | EQ 10 bandas + preamp verificável, presets salvos | Render manual com `AVAudioEngine` comum (funciona em debug); presets em `app_setting` (JSON) |
| AUD-05 | ReplayGain faixa/álbum sem regravar | `AudioFile` lê gain/peak; ganho em `outputVolume` do mixer (aceita > 1); limite por pico |
| AUD-06 | Gapless | `enqueue` na `nowPlayingChanged`; mesma taxa/canais é contínuo com a cadeia; taxa diferente reconfigura |
| AUD-07 | Troca de dispositivo sem travar | Handler do SFB reconecta mixer→saída e reinicia; delegate `audioEngineConfigurationChange`; reinstalar tap por segurança; validação humana com hardware |
</phase_requirements>

## Stack Padrão

### Núcleo
| Biblioteca | Versão | Propósito | Por que é padrão |
|------------|--------|-----------|------------------|
| SFBAudioEngine | 0.14.0 (já resolvida) | Decoders, `AudioPlayer`, fila gapless, metadados com ReplayGain | Já no projeto; fonte lido nesta pesquisa [VERIFIED: .build/checkouts/SFBAudioEngine] |
| AVFoundation (`AVAudioUnitTimePitch`, `AVAudioUnitEQ`, `AVAudioMixerNode`) | SDK do sistema | Velocidade, EQ, balanço/ganho | Nós padrão; todos testados nesta pesquisa |
| Accelerate/vDSP | SDK do sistema | RMS (`vDSP_rmsqv`), pico (`vDSP_maxmgv`), janela Hann, FFT (`vDSP_fft_zrip`) | Padrão para DSP no macOS; usados nos experimentos |
| Swift Testing | toolchain 6.4 (CLT) | Testes (`./scripts/test.sh`) | Já é o framework do projeto [VERIFIED: scripts/test.sh, Fase 1] |

Sem dependências novas de SwiftPM. Toolchain: Swift 6.4 (swiftlang-6.4.0.34.1), arm64, macOS 27 [VERIFIED: `swift --version`]. O pacote usa tools 5.9, plataforma macOS 14; o módulo `Synchronization`/`Atomic` exige macOS 15, **não usar** (alvo é 14) [ASSUMED: requisito de disponibilidade do módulo Synchronization].

### Alternativas consideradas
| Em vez de | Poderia usar | Troca |
|-----------|--------------|-------|
| TimePitch | `AVAudioUnitVarispeed` | Varispeed muda o tom (estilo fita); CONTEXT trava TimePitch |
| Pan em `AVAudioMixerNode` | Nó de balanço próprio (render block) | Mais código e risco; o `pan` do mixer deu balanço correto |
| Ganho RG em `outputVolume` do mixer | `AVAudioUnitEQ.globalGain` | globalGain já é do preamp; somar os dois dificulta clamp (±24) e testes |
| Tap do AVAudioEngine | Tap no render block do SFB | Não existe gancho público no `sourceNode` do SFB |

## Padrões de Arquitetura

### Diagrama de fluxo

```
 arquivo -> SFB decoder (thread de decodificação) -> ring buffer
                                    |
                 AVAudioSourceNode (SFB, render pull)   <- currentTime/totalTime (domínio do conteúdo)
                                    |
                      AVAudioUnitTimePitch (rate 0.5-2.0)
                                    |
                    AVAudioUnitEQ (10 bandas + globalGain=preamp)
                                    |
              AVAudioMixerNode "balanço" (pan; outputVolume = ganho ReplayGain)
                                    |
        AVAudioMixerNode principal (SFB)  (outputVolume = volume do app)  --tap--> medidor (RMS/pico + 1024 amostras)
                                    |                                              |
                              outputNode (dispositivo)                    snapshot (lock curto, trylock) -> timer UI 30-60 Hz
                                                                                   |-> FFT/balística (função pura) -> LevelMeter / espectro
 Eventos do SFB (thread própria): nowPlayingChanged/renderingStarted -> main: faixa atual, ganho RG, enqueue da próxima
                                   audioEngineConfigurationChange     -> main: reler formato, reinstalar tap
                                   reconfigureProcessingGraph         -> religa cadeia, retorna TimePitch
```

### Estrutura recomendada
```
Sources/WineupCore/Audio/        # puro: EqMath, RateMapping, ReplayGainMath, MeterMath (FFT/balística), EqPreset (+codec)
Sources/WineupAudio/             # EffectChain, SFBAudioEngineAdapter, LevelTap, ReplayGainReader
Sources/WineupAudioCheck/        # executável de verificação (release) com render offline pelo caminho SFB real
Sources/WineupLibrary/Settings/  # AppSettingEqPresetStore (app_setting)
Tests/WineupAudioTests/          # EffectChain/EQ/pan/ganho com AVAudioEngine comum (debug ok)
Tests/WineupCoreTests/           # matemática pura
```

### Padrão 1: cadeia instalada uma vez, religada inteira no delegate
**O quê:** instalar `TimePitch → EQ → balanço → mainMixer` em `modifyProcessingGraph` antes de qualquer `play`; no delegate religar os três elos com o novo formato e **retornar o primeiro nó** (`timePitch`). Evidência: o SFB faz `disconnectNodeOutput(sourceNode)` e depois `connect(sourceNode, to: node, format:)` com o nó retornado (`AudioPlayer.mm:2823-2828`); o delegate só é chamado se a ligação atual do `sourceNode` não for o `mainMixerNode` (`:2818-2819`), o que vale para a cadeia.
```swift
// Verificado nesta pesquisa (release, render manual): 44.1 st -> 48 mono -> 96 st -> 44.1 st, som contínuo em todas.
func audioPlayer(_ p: AudioPlayer, reconfigureProcessingGraph engine: AVAudioEngine,
                 with format: AVAudioFormat) -> AVAudioNode {
    engine.connect(timePitch, to: eq, format: format)
    engine.connect(eq, to: balance, format: format)
    engine.connect(balance, to: engine.mainMixerNode, format: format)
    return timePitch
}
```
Instalação inicial (nós `attach`, `disconnectNodeOutput(sourceNode)`, quatro `connect` com `sourceNode.outputFormat(forBus: 0)`) como em `AudioEngineService.insertEqualizer`, só que com a cadeia completa.

### Padrão 2: tap único no `mainMixerNode`
Instalar com `installTap(onBus: 0, bufferSize: 1024, format: nil)`, dentro ou fora de `modifyProcessingGraph` (ambos testados). O formato do mixer principal é estável (estéreo float na taxa do grafo), então `floatChannelData![1]` existe; um tap no EQ recebe o formato da fonte (mono em fontes mono) e `[1]` falharia. Só pode haver um tap por barramento: **instalar duas vezes no mesmo barramento lança NSException** (`required condition is false: nullptr == Tap()`), então sempre `removeTap(onBus:)` antes de reinstalar.
No tap: `vDSP_rmsqv`/`vDSP_maxmgv` por canal e cópia de até 1024 amostras (mix mono) para buffer pré-alocado; publicar num snapshot protegido por `OSAllocatedUnfairLock.withLockIfAvailable` (não bloqueia: descarta o quadro se o leitor estiver lendo). FFT, Hann (calculada uma vez), `FFTSetup` único, bandas log (≈20 de 40 Hz a 16 kHz) e decaimento ficam no lado da UI.

### Padrão 3: matemática pura em WineupCore
- Velocidade: slider `s∈[0,1]` → `rate = 0.5 * 4^s` (0,5→1,0 em s=0,5, 2,0 em s=1); inverso com `log`. O slider atual (padrão 0,5) vira 1,0x sem migração.
- Balanço: `pan = balance * 2 - 1`.
- Ganho efetivo do EQ: `globalGain = clamp(preamp + autoComp, -24, 24)`, `autoComp = -max(0, maiorGanhoDeBanda)`.
- RG: `dB = modo == .album ? (album ?? track) : (track ?? album)`; `linear = 10^(dB/20)`; se `preventClipping` e `peak > 0`, `linear = min(linear, 1/peak)`; sem tag → 1,0.
- Tempo restante: `(total - atual) / rate`.

### Anti-padrões
- **Tap/nó fora do trecho:** qualquer `connect` que mude quem alimenta o `outputNode` viola o assert; medido: `disconnectNodeInput(outputNode)` + inserir nó entre mixer e saída aborta com `Illegal AVAudioEngine configuration` em debug.
- **Contar com o assert em release:** os asserts do SFB estão **desligados** em release (o mesmo `AudioPlayer` renderizou offline em release e abortou em debug no assert de host time). Um grafo ilegal em release não aborta, apenas quebra o som. A regra vale nos dois builds.
- **Volume do app via `player.setVolume`:** grava no volume do dispositivo (HAL); some silenciosamente em dispositivos sem controle (o código atual faz `try?`). Usar `mainMixerNode.outputVolume`.
- **Reinstalar cadeia durante reprodução** em vez de uma vez na inicialização.
- **Usar `play(next)` no fim** em vez de `enqueue`.

## Não Reinventar

| Problema | Não construir | Usar | Por quê |
|----------|---------------|------|---------|
| Time-stretch com tom preservado | Resampler/WSOLA | `AVAudioUnitTimePitch` | Medido: 0,5x a 2,0x corretos, RMS constante |
| Equalizador | Biquads próprios | `AVAudioUnitEQ` | +12/-12 dB exatos no centro das 10 bandas |
| Balanço | Nó de render próprio | `AVAudioMixerNode.pan` | Medido: balanço correto em estéreo, mono e só-esquerda |
| Gapless e fila | Fila própria com `play` | `AudioPlayer.enqueue` | O SFB decodifica adiante e junta no buffer |
| Tags/ReplayGain | Parser próprio | `AudioFile(readingPropertiesAndMetadataFrom:)` | Já suporta Xiph (FLAC/Ogg/Opus), ID3v2, APE e MP4 |
| FFT | DFT manual | `vDSP_fft_zrip` | Verificado nos experimentos |
| Reconexão pós troca de dispositivo | Reiniciar engine à mão | handler interno do SFB | `handleAudioEngineConfigurationChange` já reconecta e reinicia |

## Respostas às perguntas de prioridade (com evidência)

### 1. O que `modifyProcessingGraph` permite; tap; sobrevivência
- Implementação (`AudioPlayer.mm:1034-1044`): pega `engineMutex_`, executa o bloco e faz `assert(inputConnectionPointForNode(outputNode).node == mainMixerNode)`. Nada mais é verificado. [VERIFIED: fonte]
- Experimentos (release, render manual, sem som): tap em `mainMixerNode` instalado dentro do bloco: entregou ≈43,2 mil frames por segundo renderizado em todas as quatro faixas e **continuou** através de três `reconfigureProcessingGraph` (44,1→48 mono→96→44,1). Tap em `AVAudioUnitEQ` e em `mainMixerNode` instalados fora do bloco também funcionaram e sobreviveram à troca para mono 48 kHz. Em build **debug** com asserts ativos, instalar/remover taps em mixer e EQ dentro de `modifyProcessingGraph` não abortou. A inserção ilegal (mixer extra entre mixer principal e saída) abortou com `Illegal AVAudioEngine configuration`. [VERIFIED: experimento]
- Resposta ao [VERIFICAR] 3: tap no mixer/EQ **não** conta como alterar o grafo e **sobrevive** a `reconfigureProcessingGraph`. Local escolhido: `mainMixerNode`.
- Limite do experimento: a taxa do mixer foi fixa (render manual). Mudança real de taxa de hardware não foi reproduzível sem dispositivo; mitigação: reinstalar o tap em `audioEngineConfigurationChange` e ler `sampleRate` de cada buffer [ASSUMED que o tap sobrevive à troca real de taxa; a reinstalação torna isso irrelevante].

### 2. Ordem e religação; mono e pan
- Ordem recomendada: `TimePitch → EQ → balanço(mixer) → mainMixer`. TimePitch primeiro para o EQ atuar no sinal já esticado; EQ antes do ganho/balanço para o ganho RG e o pan não alterarem o que o EQ vê.
- O delegate retorna `timePitch` e religa `timePitch→eq→balance→mainMixer` com `format`. Mono 48 kHz, estéreo 96 kHz e voltar a 44,1 kHz funcionaram; `reconfigure` foi chamado exatamente nas trocas de formato (3 vezes em 4 faixas, a primeira de mesmo formato não chama). [VERIFIED: experimento]
- Pan (nível RMS, tom de amplitude 0,5 = -9,03 dBFS por canal em estéreo):

| Fonte | pan | L (dB) | R (dB) |
|-------|-----|--------|--------|
| estéreo | 0 | -9,03 | -9,03 |
| estéreo | -1 | -9,03 | silêncio |
| estéreo | +1 | silêncio | -9,03 |
| mono | 0 | -12,04 | -12,04 |
| mono | -1 | -9,03 | silêncio |
| mono | +1 | silêncio | -9,03 |
| só-esquerda | 0 | -9,03 | silêncio |
| só-esquerda | +1 | silêncio | silêncio |

  Comportamento de balanço (não de panorama) para estéreo; mono centralizado cai 3 dB (lei de pan). Aceitável e documentar. [VERIFIED: experimento]

### 3. Relógio com taxa
`currentTime = framePosition / sampleRate` do decoder (`AudioPlayer.h:561-578`) e os frames são contados na pulsação do `sourceNode`, que o TimePitch puxa à taxa × saída. Medido, 2,0 s de saída:

| rate | currentTime | esperado |
|------|-------------|----------|
| 1,0 | 1,974 | 2,0 |
| 1,5 | 2,961 | 3,0 |
| 0,5 | 0,987 | 1,0 |
| 2,0 | 3,947 | 4,0 |

(~1,3% a menos = latência inicial de ~26 ms.) Conclusão: progresso, barra de busca (`seek(position:)`) e letras `.lrc` usam `currentTime` direto; **não** multiplicar pela taxa. O que muda: `remainingSeconds = (total - atual) / rate` e qualquer temporizador de pré-carga baseado em parede. A primeira medição a 2,0x (3,57) foi artefato do passo do laço de render (8 ms); com 25 ms deu 3,947. [VERIFIED: experimento]

### 4. Gapless e sinalização de troca de faixa
- `enqueue(url)` mantém fila; o SFB começa a decodificar o próximo decoder assim que há espaço (`decodingStarted` da faixa 2 chegou ~0,1 s antes do fim da 1). Mesma taxa, canais e layout → junção sem reconfigurar (`AudioPlayer.mm:1408`, `formatWillBeGaplessIfEnqueued` em `:688`).
- Com TimePitch+EQ+pan inseridos, taxa 1,0x e 1,5x: **nenhuma** corrida de zeros > 16 frames entre a faixa 1 e 2 (sinal de seno contínuo; só a latência inicial de ~104 ms no começo e o silêncio final). Troca para 48 kHz (formato diferente): `reconfigure` chamado e buraco medido de 4120 frames (~93 ms) a 1,0x; a 1,5x não apareceu corrida > 16 frames (variação do passo do render offline), então tratar como "pode haver buraco" quando o formato muda. [VERIFIED: experimento]
- Sequência de eventos observada: `decodingStarted(B)` → `renderingComplete(A)` → `nowPlayingChanged(B)` → `renderingStarted(B)`; no fim da fila: `renderingComplete(C)` → `nowPlayingChanged(nil)` → `audioPlayerEndOfAudio`. Todos fora da main. [VERIFIED: experimento]
- Uso: no `nowPlayingChanged(decoder?)` mapear o decoder para a faixa do app (guardar `ObjectIdentifier(decoder)` → token ao criar `AudioDecoder(url:)` no adaptador, em vez de depender da URL, para suportar repetição da mesma faixa), atualizar `currentID`, aplicar ganho RG da faixa e enfileirar a vizinha (`clearQueue()` antes, para ser idempotente). `play(url)` (reprodução imediata) limpa a fila. Último item da lista: não enfileirar; `endOfAudio` → parar a UI (substitui o `onEndOfAudio → step(by: 1)` atual). Repetição/embaralhar/fila real ficam na Fase 4.

### 5. ReplayGain
- Leitura: `AudioFile(readingPropertiesAndMetadataFrom: url).metadata.replayGainTrackGain / TrackPeak / AlbumGain / AlbumPeak / ReferenceLoudness` (`Double?`). Ganhos em dB; picos lineares. Escrevi e reli numa cópia temporária: -6,5 / 0,97 / 3,25 / 0,5 voltaram idênticos (FLAC). Suporte por formato no fonte: Xiph (`REPLAYGAIN_*`, aceita "−6.50 dB"), ID3v2, APE, MP4 (`----:com.apple.iTunes:replaygain_*`). **Opus `R128_TRACK_GAIN` não é lido** pelo SFB (nenhuma ocorrência de R128 em Metadata/); faixas Opus ficam sem ganho nesta fase (documentar). O app nunca grava tags nesse fluxo. [VERIFIED: fonte + experimento]
- O SFB não aplica ReplayGain por conta própria (nenhuma referência em `Player/`). [VERIFIED: fonte]
- Onde aplicar: `outputVolume` do mixer de balanço. Medido: 0,5→-6,02 dB; 2,0→+6,02 dB; 4,0→+12,04 dB (aceita > 1, sem corte). Alternativa descartada: `eq.globalGain` (já é o preamp). O volume do app fica separado em `mainMixerNode.outputVolume` (2,0 deu +6,02 dB). [VERIFIED: experimento]
- Troca de ganho no limite de faixas: aplicar em `nowPlayingChanged`/`renderingStarted` da nova faixa (a latência do evento é de alguns ms, aceitável; em modo álbum o ganho é igual entre faixas do mesmo álbum e nada muda). Ler o RG da próxima faixa no momento do `enqueue` (fora da main). `outputVolume` muda instantaneamente (sem rampa); um clique em salto grande de ganho é possível [ASSUMED].
- Proteção de pico: `linear = min(10^(dB/20), 1/peak)`. Não cobre o realce do EQ: com as 10 bandas em +12 dB e seno de 0,5, o pico medido foi 5,19 (+14,3 dBFS), por sobreposição de bandas (>12 dB). A regra `autoComp = -max(banda)` é só aproximação; ver Questões em Aberto.

### 6. Verificar o EQ objetivamente (apenas CLT)
`AVAudioEngine` comum + `AVAudioSourceNode` + `AVAudioUnitEQ` + `enableManualRenderingMode(.offline, ...)` + `renderOffline`, medindo com `vDSP_rmsqv`. Rodou em **build debug** (portanto serve para `swift test`). Resultados (configuração do app: paramétrico, `bandwidth = 1`):
- Cada uma das 10 bandas, tom no centro da banda: +12 → +12,00 dB; -12 → -12,00 dB (todas as 10).
- Ruído branco, preset Bass Boost `[8,6,4,2,0,0,0,0,0,0]` vs Flat, energia por faixa via FFT: 40–80 Hz +6,9 dB; 140–200 Hz +7,3 dB; 500–700 Hz +3,1 dB; 3–7 kHz +0,03 dB; 10–14 kHz 0,00 dB.
- `globalGain`: -96 → -96,00; +24 → +24,00; +40 → +40,00 (o clamp de ±24 do EQ não impede; clampar na nossa camada).
- Pelo caminho SFB com a cadeia: banda 1 kHz +12 → +12,00 dB; preamp -6 → -6,00 dB; bypass → 0,00 dB. [VERIFIED: experimento]
Receita de teste: gerar o sinal, renderizar bloco a bloco (4096), descartar os primeiros ~8192 frames (transitório) e comparar RMS contra a mesma renderização com EQ plano. O passo da coluna "3 oitavas acima" do experimento foi inválido para bandas >= 5 kHz (alias acima de Nyquist) e não deve ser reaproveitado.

### 7. Troca de dispositivo
- O SFB registra `AVAudioEngineConfigurationChangeNotification` para o seu engine (`AudioPlayer.mm:594-597`); o handler (`:2559-2661`) limpa as flags, lê o formato do `outputNode`, e se mudou (taxa/canais) para o engine, reconecta mixer→saída com o formato novo, `prepare`, **reinicia** o engine e restaura `engineRunning|playing`, e então chama `audioPlayer(_:audioEngineConfigurationChange:)`. Se o formato da saída vier inválido (transitório), pula a reconexão. Falha ao reiniciar chama `encounteredError`. [VERIFIED: fonte]
- Simulação (postando a notificação no engine em render manual): engine continua rodando, `playbackState` = playing, RMS de saída e `currentTime` seguiram, tap continuou entregando. Hardware real (fones, AirPods, HDMI) **não** foi testado: é validação humana obrigatória. [VERIFIED parcial: experimento; ASSUMED para hardware]
- No app: implementar `audioEngineConfigurationChange` como "relê formato/taxa para o readout, reinstala o tap (remove+install), sem tocar em play/pause"; mostrar `statusMessage` em `encounteredError`. A saída padrão do sistema é seguida pelo `outputNode` do AVAudioEngine; escolha de dispositivo específico (`setOutputDeviceID`) está fora do escopo da fase [ASSUMED].

## Pegadinhas Comuns

### 1. Testar o `AudioPlayer` do SFB offline em `swift test`
**Problema:** o assert `kAudioTimeStampHostTimeValid` (`AudioPlayer.mm:226`) aborta o processo em debug quando o engine está em render manual. **Evitar:** `swift test` só testa `EffectChain`/matemática com `AVAudioEngine` comum; o caminho SFB real é verificado pelo executável de release `wineup-audiocheck` (asserts compilados fora). **Sinal:** `Assertion failed: ... hostTimeForFrameOffset`.

### 2. Dois taps no mesmo barramento
**Problema:** `installTap` repetido lança NSException e derruba o app. **Evitar:** encapsular em `LevelTap.install()` que sempre faz `removeTap` antes; usar numa única função chamada na inicialização e em `audioEngineConfigurationChange`.

### 3. Enganar-se sobre dados velhos do medidor
**Problema:** com o engine parado (`stop()`), o tap não entrega buffers e o último snapshot fica congelado. **Evitar:** snapshot com carimbo de tempo; a UI trata idade > ~100 ms como silêncio e aplica decaimento. Em pausa o engine segue rodando (estado paused = engine rodando) e o tap entrega zeros [VERIFIED: doc do header `SFBAudioPlayerPlaybackStatePaused`].

### 4. Religar só parte da cadeia no delegate
**Problema:** mudar de estéreo para mono sem religar os elos internos deixa formatos inconsistentes. **Evitar:** o delegate religa os três elos e retorna o primeiro nó; teste do `wineup-audiocheck` percorre 44,1 st → 48 mono → 96 st.

### 5. Volume do app no lugar errado
`player.setVolume` mexe no volume do dispositivo e falha em HDMI/alguns dispositivos; engolir o erro com `try?` esconde. Migrar o slider de volume para `mainMixerNode.outputVolume` (0…1).

### 6. Clipping por EQ
Ver item 5 acima: sobreposição de bandas excede a soma ingênua. Compensar o preamp e, se necessário, limitador.

### 7. Opus sem ganho; ReplayGain ausente
Sem tag → ganho 1,0 (não inventar). Documentar que Opus (R128) não é lido.

### 8. Swift concorrência
O delegate chama fora da main; o adaptador deve ser `@unchecked Sendable` com estado protegido e enviar callbacks para main. Compilar o target com `-strict-concurrency=complete` como WineupCore.

## Exemplos de Código

### Cadeia de efeitos testável (sem SFB)
```swift
// Fonte: padrão validado nesta pesquisa (experimento EQTest, debug)
public final class EffectChain {
    public let timePitch = AVAudioUnitTimePitch()
    public let eq = AVAudioUnitEQ(numberOfBands: 10)
    public let balance = AVAudioMixerNode()          // pan + outputVolume (ganho RG)
    public var first: AVAudioNode { timePitch }
    public func attach(to engine: AVAudioEngine) { [timePitch, eq, balance].forEach(engine.attach) }
    public func connect(_ engine: AVAudioEngine, from source: AVAudioNode, to sink: AVAudioNode, format: AVAudioFormat) {
        engine.connect(source, to: timePitch, format: format)
        reconnectInternal(engine, to: sink, format: format)
    }
    public func reconnectInternal(_ engine: AVAudioEngine, to sink: AVAudioNode, format: AVAudioFormat) {
        engine.connect(timePitch, to: eq, format: format)
        engine.connect(eq, to: balance, format: format)
        engine.connect(balance, to: sink, format: format)
    }
}
```

### Render offline para teste do EQ
```swift
// Fonte: experimento desta pesquisa (funciona em debug)
let fmt = AVAudioFormat(standardFormatWithSampleRate: 44100, channels: 2)!
engine.attach(src); engine.attach(eq)
engine.connect(src, to: eq, format: fmt); engine.connect(eq, to: engine.mainMixerNode, format: fmt)
try engine.enableManualRenderingMode(.offline, format: fmt, maximumFrameCount: 4096)
try engine.start()
let buf = AVAudioPCMBuffer(pcmFormat: engine.manualRenderingFormat, frameCapacity: 4096)!
_ = try engine.renderOffline(4096, to: buf)   // repetir; descartar ~8192 frames; vDSP_rmsqv
```

### Render offline pelo SFB (só release / executável de verificação)
```swift
// Antes: engine.stop() (o SFB já deu prepare; enableManualRenderingMode exige engine não inicializado, erro -80801).
player.modifyProcessingGraph { engine in
    engine.stop()
    try! engine.enableManualRenderingMode(.offline, format: fmt, maximumFrameCount: 4096)
}
try player.play(url)
// Loop: renderOffline(1024) + usleep(~8-25 ms) para o decoder acompanhar (o decoder é assíncrono)
```

### Leitura de ReplayGain
```swift
let file = try AudioFile(readingPropertiesAndMetadataFrom: url)   // fora da main
let m = file.metadata
let gain = m.replayGainTrackGain, peak = m.replayGainTrackPeak    // Double? (dB, linear)
```

## Estado da Arte

| Antigo | Atual | Impacto |
|--------|-------|---------|
| "SFB currentTime ignora a taxa" (PITFALLS 3, hipótese) | `currentTime` é tempo de conteúdo (medido) | Sem fator na barra/letras; corrigir só o restante em parede |
| Volume via `player.setVolume` (código atual) | `mainMixerNode.outputVolume` | Volume do app independente do dispositivo |
| Só EQ religado no delegate | Cadeia inteira religada | Necessário para velocidade/balanço/ganho |

## Log de Suposições

| # | Afirmação | Seção | Risco se errada |
|---|-----------|-------|-----------------|
| A1 | `Synchronization.Atomic` não está disponível com alvo macOS 14 | Stack | Baixo: só muda o mecanismo de snapshot |
| A2 | Callbacks de tap do AVAudioEngine não rodam na thread de render em tempo real (por isso `withLockIfAvailable` basta) | Padrão 2 | Médio: se fosse RT, usar buffer sem lock via shim C |
| A3 | Tap sobrevive a troca real de taxa de hardware (simulado só em render manual) | Resp. 1/7 | Baixo: reinstalamos no `audioEngineConfigurationChange` |
| A4 | Troca de dispositivo real (AirPods/HDMI) funciona sem travar | Resp. 7 | Alto para AUD-07: exige teste humano |
| A5 | `outputVolume` com salto grande pode dar clique | Resp. 5 | Baixo |
| A6 | HDMI/alguns dispositivos não aceitam `setVolume` HAL | Anti-padrões | Baixo (a recomendação evita) |
| A7 | `AVAudioEngine` segue o dispositivo de saída padrão sozinho | Resp. 7 | Médio |
| A8 | Opus R128 não suportado pelo SFB 0.14 (só ausência de ocorrências no fonte) | Resp. 5 | Baixo |
| A9 | Limitador `PeakLimiter` (AU) serve como seguro pós-EQ | Questões em aberto | Baixo (não testado) |

## Questões em Aberto

1. **Compensação de preamp e sobreposição de bandas**
   - Sabemos: todas +12 → +20 dB no pico; `-max(banda)` não basta.
   - Falta: política (compensação por resposta calculada na grade de frequências vs limitador).
   - Recomendação: função pura `EqMath.peakGain(bands:)` calculada por soma de curvas na grade + teste contra render offline; limitador só se a medida divergir.
2. **Waveform real**: `WaveformView` é decorativa (semente do id). AUD-01 pede espectro e VU, não forma de onda. Recomendação: manter como barra de busca nesta fase; overview real fica para Fase 5 (ou plano opcional).
3. **Colunas de RG no banco**: ler RG sob demanda no `enqueue` (sem migração). Colunas na varredura só se a Fase 4 precisar.
4. **Bypass do TimePitch a 1,0x**: reduziria latência (~100 ms iniciais observados) mas não foi testado.

## Disponibilidade de Ambiente

| Dependência | Necessária para | Disponível | Versão | Fallback |
|-------------|-----------------|------------|--------|----------|
| Swift toolchain (CLT) | build/teste | sim | 6.4 (swiftlang-6.4.0.34.1) | — |
| SFBAudioEngine checkout | adaptador | sim | 0.14.0 em `.build/checkouts` | — |
| `afconvert` | fixtures FLAC/M4A | sim | sistema | gerar WAV em Swift |
| Dispositivo de saída de áudio | `swift test` com AVAudioEngine | sim nesta máquina | — | render manual não precisa de saída audível |
| Fones/AirPods/HDMI | AUD-07 humano | não verificado | — | validação manual no fim |
| Disco | builds | 32 GiB livres (29% usado) | — | — |

Bloqueios: nenhum.

## Arquitetura de Validação

### Framework de teste
| Propriedade | Valor |
|-------------|-------|
| Framework | Swift Testing (CLT, via `./scripts/test.sh`, com `-plugin-path` do TestingMacros) |
| Config | `Package.swift` (adicionar `WineupAudioTests` e o executável `wineup-audiocheck`) |
| Comando rápido | `./scripts/test.sh --filter WineupAudioTests` e `--filter WineupCoreTests` |
| Suíte completa | `swift build -c release && ./scripts/test.sh` |
| Verificação do caminho SFB | `swift build -c release --product wineup-audiocheck && .build/release/wineup-audiocheck` (sem som; render manual) |
| Fim da fase | `./scripts/build-app.sh` (smoke de reprodução com `WINEUP_LIBRARY_PATH` temporário) |

### Requisitos → testes
| Req | Comportamento | Tipo | Comando automatizado | Arquivo existe? |
|-----|---------------|------|----------------------|-----------------|
| AUD-01 | RMS/pico e bandas do espectro de um seno de 1 kHz caem na banda correta; silêncio → 0; snapshot velho (>100 ms) vira silêncio; balística decai | unit (WineupCore) | `./scripts/test.sh --filter MeterMathTests` | Wave 0 |
| AUD-01 | Tap em `mainMixerNode` entrega RMS ≈ nível do sinal por `EffectChain`+engine comum; zeros em silêncio | integração (debug, render manual) | `./scripts/test.sh --filter LevelTapTests` | Wave 0 |
| AUD-01 | Pelo SFB real: tap entrega frames nas quatro trocas de formato (44,1 st/48 mono/96 st) | executável release | `.build/release/wineup-audiocheck meter` | Wave 0 |
| AUD-02 | slider↔taxa (0,5…2,0; 0,5→1,0) e restante em parede `/taxa` | unit | `./scripts/test.sh --filter RateMappingTests` | Wave 0 |
| AUD-02 | `currentTime` após 2 s de saída a 1,5x ≈ 3,0 s (±5%) pelo SFB | executável release | `.build/release/wineup-audiocheck rate` | Wave 0 |
| AUD-03 | pan -1/0/+1 em estéreo e mono: canal oposto < -60 dB, canal alvo ≈ -9 dB (±0,5) | integração (debug) | `./scripts/test.sh --filter BalanceTests` | Wave 0 |
| AUD-04 | +12/-12 dB em cada uma das 10 bandas (±0,3 dB); preamp -6 → -6 dB; bypass → 0 dB; preset Bass Boost eleva 40–200 Hz > 5 dB vs Flat | integração (debug, render manual) | `./scripts/test.sh --filter EqualizerEffectTests` | Wave 0 |
| AUD-04 | presets (salvar/renomear/apagar) reabrem após reabrir `LibraryDatabase` temporário; JSON inválido ignorado | unit/integ. (WineupLibrary) | `./scripts/test.sh --filter EqPresetStoreTests` | Wave 0 |
| AUD-04 | autoComp/clamp do preamp (puros) | unit | `./scripts/test.sh --filter EqMathTests` | Wave 0 |
| AUD-05 | ganho linear `10^(dB/20)`, álbum→faixa fallback, sem tag = 1,0, limite por pico | unit | `./scripts/test.sh --filter ReplayGainMathTests` | Wave 0 |
| AUD-05 | leitura de RG de FLAC temporário com tags gravadas pelo teste (cópia em `TempDir`) e arquivo original intacto (hash igual) | integração | `./scripts/test.sh --filter ReplayGainReaderTests` | Wave 0 |
| AUD-05 | `outputVolume` do balanço aplica o ganho (+6 dB para 2,0) | integração (debug) | `./scripts/test.sh --filter EffectChainGainTests` | Wave 0 |
| AUD-06 | duas faixas de mesmo formato via `enqueue`: nenhuma corrida de zeros > 16 frames; `nowPlayingChanged` na ordem A→B→nil→`endOfAudio` | executável release | `.build/release/wineup-audiocheck gapless` | Wave 0 |
| AUD-06 | lógica de "qual faixa enfileirar" (vizinha, fim da lista, idempotência) | unit (WineupCore) | `./scripts/test.sh --filter NextTrackPlannerTests` | Wave 0 |
| AUD-07 | notificação `AVAudioEngineConfigurationChange` simulada: engine segue rodando, `isPlaying`, RMS > 0 depois | executável release | `.build/release/wineup-audiocheck configchange` | Wave 0 |
| AUD-07 | Trocar para fones/AirPods/HDMI durante a música sem parar nem travar | manual (hardware) | checklist humano no fim da fase | n/a |
| Todos | App empacotado toca FLAC/M4A/WAV com cadeia ativa sem cair | smoke | `./scripts/build-app.sh` | existe (Fase 1) |

### Taxa de amostragem
- **Por commit de tarefa:** `swift build -c release` e `./scripts/test.sh --filter <suíte da tarefa>`
- **Por merge de onda:** `swift build -c release && ./scripts/test.sh` e `wineup-audiocheck` (todas as seções)
- **Gate da fase:** suíte completa verde + `./scripts/build-app.sh` + checklist humano de AUD-07 antes de `/gsd-verify-work`

### Lacunas da Onda 0
- [ ] Target `WineupAudio` + `Tests/WineupAudioTests/` + executável `wineup-audiocheck` no `Package.swift`
- [ ] Helpers de teste: gerador de seno/ruído/WAV em `TempDir` (`Tests/WineupLibraryTests/Support/WAVFixture.swift` e `TempDir.swift` já existem para a biblioteca; reaproveitar o padrão), `offlineRender` e `rms/db`
- [ ] `adapter.withEngine`/gancho interno para o executável de verificação habilitar render manual (com `engine.stop()` antes)
- [ ] Sem instalação de framework (Swift Testing já funciona)

## Domínio de Segurança

| Categoria ASVS | Aplica | Controle |
|----------------|--------|----------|
| V2/V3 Autenticação/Sessão | não | — |
| V4 Controle de acesso | não | Sem sandbox por decisão do projeto |
| V5 Validação de entrada | sim | JSON de presets validado (tamanho de 10 bandas, faixa ±12 dB, nome não vazio); valores de RG finitos e limitados (ex.: ±30 dB, pico > 0) |
| V6 Criptografia | não | — |

| Ameaça | STRIDE | Mitigação |
|--------|--------|-----------|
| Arquivo de áudio/tag malformado derruba decoder | Denial of service | Decoders do SFB; tratar erros em `encounteredError`/`decodingAborted`; nunca confiar em valores de RG (NaN/Inf) |
| Preset corrompido no `app_setting` | Tampering | Decodificar com fallback para presets embutidos |
| Ganho extremo por tag maliciosa | Tampering | Clamp de dB e `min(…, 1/peak)`; teto de ganho |

## Fontes

### Primárias (ALTA)
- `.build/checkouts/SFBAudioEngine/Sources/CSFBAudioEngine/Player/AudioPlayer.mm` (linhas 223-229, 586-597, 653-696, 1016-1044, 1395-1480, 2090-2262, 2440-2540, 2557-2661, 2769-2857) e `AudioPlayer.h` (561-581)
- `.../include/SFBAudioEngine/SFBAudioPlayer.h`, `SFBAudioMetadata.h`, `Metadata/SFBAudioMetadata+TagLib*.mm`
- Experimentos nesta sessão (pacote temporário com dependência local de path, apagado ao final; nada alterado no repositório): `chain`, `pan`, `rate`, `gapless`, `eqsfb`, `cfg`, `notap`, `dbgassert`, `eqbands`, `rg`
- Arquivos do projeto: `AudioEngineService.swift`, `PlayerState.swift`, `PlayerPanel.swift`, `LevelMeter.swift`, `WaveformView.swift`, `EqualizerPanel.swift`, `Ports.swift`, `Migrations.swift`, `scripts/*`

### Secundárias/Terciárias
- `.planning/research/PITFALLS.md` (3, 4, 5, 15, 16) e `SUMMARY.md` [VERIFICAR 3–7]: itens 3 e 4 resolvidos aqui; a hipótese de "currentTime sem taxa" foi refutada.

## Metadados

**Confiança:** pilha ALTA (verificada no fonte e por experimento); arquitetura ALTA; armadilhas ALTA, exceto hardware real (AUD-07), MÉDIA.
**Pesquisado em:** 2026-10-20 · **Válido até:** enquanto o SFBAudioEngine permanecer em 0.14.x (30 dias)
