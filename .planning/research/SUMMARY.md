# Resumo da Pesquisa do Projeto

**Projeto:** Wineup Player
**Domínio:** player de música local nativo para macOS (estilo Winamp) com assistente de correção de biblioteca (Library Fixer)
**Pesquisado:** 2026-10-19 (síntese em 2026-10-20)
**Confiança:** MÉDIA

## Resumo Executivo

O Wineup Player é um player local em Swift/SwiftUI sobre SFBAudioEngine + AVAudioEngine. Hoje é um protótipo de ~1400 linhas em um único alvo executável: objeto-deus (`PlayerState`), IDs de faixa por índice, biblioteca só em memória, VU/espectro simulados e nenhum teste. Players maduros (Swinsian, foobar2000, Cog, Audacious) e o Mixxx convergem no mesmo desenho: SQLite separando arquivo físico de gravação lógica, varredura incremental, núcleo sem UI e motor de áudio atrás de uma porta. A recomendação é seguir esse desenho em **camadas horizontais** (escolha do usuário), com as portas (protocolos) num `WineupCore` puro para testar serviços com fakes.

Máximo de frameworks da Apple e poucas dependências novas: **GRDB** (SQLite, FTS5, observação) e **ZIPFoundation** (skins); **Chromaprint** só no fim, como dylib; tags gravadas pela própria SFBAudioEngine (`writeMetadata`), sem TagLib separado.

O diferencial (Library Fixer com prévia, confiança explicada e desfazer real) é também o maior risco ao Core Value ("nunca danificar os arquivos"): backup, verificação e journal precisam existir e estar testados **antes** da primeira gravação, mesmo que a UI do Fixer venha por último.

Riscos dominantes: (1) gravação de tags corrompendo/degradando arquivos; (2) quebrar a restrição do grafo do SFB (só `sourceNode → mainMixerNode`) ao inserir velocidade/balanço/medidores; (3) não conseguir rodar testes só com Command Line Tools; (4) varredura/SQLite que não escala; (5) "correções" que pioram tags (lançamento errado do MusicBrainz). Risco estrutural das camadas horizontais: valor visível tarde — mitigado com um caminho ponta a ponta mínimo ao fim de cada fase.

## Principais Descobertas

### Stack Recomendada (detalhes em STACK.md)
Swift 6.4 (CLT), tools-version 5.9, alvo macOS 14+.
- **GRDB.swift 7.11.1 (MIT):** migrations, FTS5, `ValueObservation`, `DatabasePool` (WAL). SwiftData/Core Data descartados (exigem ferramentas do Xcode).
- **ZIPFoundation 0.9.20 (MIT):** `.wsz` e pacotes de skin sem extrair para disco.
- **SFBAudioEngine 0.14+ (em uso):** reprodução, leitura/escrita de tags, ReplayGain.
- **Chromaprint 1.6.x** como dylib embutido com KissFFT ou vDSP (nunca FFTW, GPL). Adiado para a fase de provedores.
- Apple: Accelerate/vDSP (espectro, RMS/pico), `AVAudioUnitTimePitch` (velocidade), pan (balanço), MediaPlayer (Now Playing), `URLSession`.
- **Swift Testing** (presente nos CLT) em vez de XCTest; parser `.lrc` próprio; skin própria (`skin.json` + PNG).
- **Fora:** AudioKit, TagLib direto, Alamofire, pacotes LRC de terceiros, código Winamp/Mixxx/Cog.

### Funcionalidades (detalhes em FEATURES.md)
- **Table stakes:** biblioteca persistente com varredura incremental; navegação artista/álbum/faixa/gênero; busca FTS5; fila, playlists (M3U/M3U8), repetir/embaralhar, restauração de estado, gapless; teclas de mídia, Now Playing, atalhos clássicos; capas com fallback; letras embutidas e `.lrc`; EQ com presets persistentes; velocidade/balanço, espectro e VU reais; ReplayGain não destrutivo; edição simples de tags pelo pipeline seguro; modo mini; acessibilidade.
- **Diferenciais:** Library Fixer em assistente com confiança explicada; discografia com Singles/EP/Desconhecido como visão virtual; dedup single↔álbum; duplicatas (só relatório); reconhecimento acústico opcional com modo offline; skins próprias; `.wsz` como subconjunto declarado.
- **Adiar (v2+):** fingerprint/provedores online, dedup semântico, `.wsz`, visualizações avançadas, painéis destacáveis, rename/organização, Sparkle.
- **Nunca:** plugins Winamp, streaming/podcasts, scrobbling por padrão, correção silenciosa, remoção automática de duplicatas.

### Arquitetura (detalhes em ARCHITECTURE.md)
Camadas como targets SwiftPM, dependência estritamente descendente; só o executável instancia implementações concretas; dados sobem como snapshots imutáveis, comandos descem; ViewModels `@MainActor` (`@Observable`) assinam a observação do GRDB; eventos do motor por `AsyncStream`.
1. `WineupCore` (Foundation puro): entidades, `Confidence`, `TagDiff`, journal, portas (`AudioEngine`, `LibraryStore`, `TagIO`, `MetadataProvider`).
2. `WineupAudio`: adaptador SFB + AVAudioEngine, cadeia timePitch → EQ → pan, medidor, espectro, gapless.
3. `WineupLibrary`: GRDB, migrations, repositórios, FTS5, `TagIO`, journal.
4. `WineupServices`: `PlaybackController`, `LibraryScanner`, `FixerPipeline`, `ArtworkResolver`, `LyricsService`, `NowPlayingBridge`.
5. `WineupUI`: ViewModels, painéis, `SkinEngine` declarativo.
6. `Wineup` (exe fino): `AppEnvironment`, MPRemoteCommandCenter, atalhos, janelas.

Modelo: `audio_file` → `recording` → `release_track` → `release` (tipo com origem `tag/inferred/user`; `unknown` nunca vira single) + `tag_snapshot`, `fixer_run/issue/change`, `journal`. "Singles" é consulta, nunca tag gravada.

### Armadilhas Críticas (detalhes em PITFALLS.md)
1. **Gravar tags in-place sem backup/verificação** → backup (`clonefile`), gravar em cópia, reler e verificar, `replaceItemAt`, journal; prévia como padrão; nenhum caminho chama `writeMetadata` fora do orquestrador.
2. **Degradar tags por formato** (ID3 2.3/2.4, frames desconhecidos, `ilst`, padding FLAC, capas grandes) → fixtures por formato com ida e volta; preservar versão ID3 e frames desconhecidos; nunca recomprimir capa sem consentimento.
3. **Violar o grafo do SFB** (já causou abort) → cadeia única entre `sourceNode` e `mainMixerNode`, religada inteira em `reconfigureProcessingGraph`; teste com 44,1 kHz, 96 kHz e mono.
4. **Trabalho na thread de áudio / relógio errado com velocidade ≠ 1** → tap só RMS/pico para buffer circular pré-alocado; FFT fora do tap; relógio, letras e Now Playing corrigidos pela taxa.
5. **Sem teste executável só com CLT** → provar `swift test` no primeiro dia; render offline (`enableManualRenderingMode`) para verificar o EQ.
6. **Varredura/SQLite que não escala e sandbox indefinido** → enumeração em duas etapas, lotes, WAL, identidade por inode/`content_hash`, itens `missing`; decidir sandbox antes do esquema de caminhos.
7. **"Correção" que piora a biblioteca** → separar erro objetivo de preferência estética; confiança por campo; usar contexto do álbum, duração e nº de faixas, nunca o primeiro resultado do MusicBrainz.

## Reconciliação de Conflitos

| Tema | Divergência | Decisão |
|---|---|---|
| Targets | STACK: 2 targets; ARCHITECTURE: 6 camadas | Adotar ARCHITECTURE; fase 1 pode começar com Core + um alvo de biblioteca, desde que as portas fiquem no Core |
| Ordem | FEATURES: biblioteca → fila → áudio; ARCH: Core → Dados → Áudio → Serviços → UI → Wiring → Fixer; PITFALLS: testes antes | Seguir ARCH com Dados logo após fundação e testes como fase 1; Dados e Áudio podem se sobrepor |
| Testes | FEATURES: adiar; demais: primeiro | Testes na fase 1 (bloqueante); só a notarização completa fica tarde, com build assinado de teste cedo |
| Framework de teste | incerto | Swift Testing como padrão; plano B: toolchain swift.org ou executável `WineupSelfTests` |
| Now Playing | MVP vs camadas | Porta e estado únicos em Serviços (fase 4); MPRemoteCommandCenter real no executável (fase 6) |
| Escrita de tags vs Fixer | Fixer tarde vs infra cedo | `TagWriter`, backup, journal, `dryRun` e fixtures na fase de Dados; Fixer só adiciona regras, prévia e UI |
| Local do backup | Application Support vs mesmo volume | Por volume ao lado da raiz da biblioteca, fallback para cópia em Application Support; mostrar espaço/retenção [VERIFICAR] |
| Velocidade | TimePitch vs Varispeed | TimePitch padrão, Varispeed opcional; relógio corrigido pela taxa |
| Tap de medição | mixer vs pós-EQ vs proibido pelo SFB | Em aberto: primeiro item da pesquisa da fase de Áudio |
| Sandbox | sem sandbox vs decidir antes de notarizar | Sem sandbox, Developer ID, hardened runtime; acesso atrás de `LibraryRoot`; registrar na fase 1 |
| Chromaprint | LGPL efetivo | Tratar como LGPL-2.1: dylib substituível, sem FFTW; auditar o tag na fase 8 |
| Concorrência | — | Manter tools 5.9; `-strict-concurrency=complete` nos targets novos; ViewModels `@MainActor` |

## Implicações para o Roadmap (8 fases, camadas horizontais)

1. **Fundação e Infraestrutura de Teste** — `WineupCore` (modelos, IDs estáveis, portas, `Confidence`, `TagDiff`, journal), executável fino, alvos de teste rodando com CLT, `MarkColor` fora do domínio, decisões (sem sandbox, `LibraryRoot`, bundle ID), build assinado de teste; o app continua tocando.
2. **Dados (WineupLibrary)** — schema/migrations GRDB (WAL), repositórios, FTS5 (`remove_diacritics`), `TagIO` de leitura, scanner incremental (inode/`content_hash`, `missing`), `tag_snapshot`; infraestrutura de escrita segura (`TagWriter`, backup, verificação, journal, `dryRun`, fixtures). *Pesquisa de fase.*
3. **Áudio Real (WineupAudio)** — porta `AudioEngine` com `AsyncStream`; cadeia timePitch → EQ → pan religada em `reconfigureProcessingGraph`; VU/espectro reais; velocidade, balanço; presets de EQ; ReplayGain não destrutivo; gapless via `enqueue`; troca de dispositivo; testes por render offline. *Pesquisa de fase (risco alto).*
4. **Serviços** — `PlaybackController` (fila, repetir, embaralhar, relógio com taxa), playlists M3U/M3U8, restauração de sessão, `ArtworkResolver`, `LyricsService` (`.lrc`), consultas de discografia virtuais, `NowPlayingBridge`, dedup determinístico na fila. **Critério: tocar arquivo vindo do banco ponta a ponta.**
5. **UI (WineupUI)** — ViewModels `@Observable`/`@MainActor`, navegação artista/álbum/single, painéis com medidores reais, letras sincronizadas, `SkinEngine` declarativo (três temas atuais como skins), acessibilidade, listas paginadas.
6. **Integração com o Sistema e Distribuição** — `AppEnvironment`, MPRemoteCommandCenter/MPNowPlayingInfoCenter reais, atalhos (Z X C V B), modo mini, persistência de janelas, `scripts/release.sh` (assinatura de dentro para fora, hardened runtime, `notarytool`, `stapler`, `.dmg`), avisos LGPL com versões exatas, teste em Mac limpo (VM tart). *Pesquisa de fase.*
7. **Library Fixer v1 (offline)** — Diagnose, Propose com confiança por campo, Preview (diff, seletivo, manual, ignorar persistente), Apply (revalida, backup, escrita, verificação, journal), Undo por lote, painel de saúde, edição simples de tags. *Pesquisa de fase.*
8. **Provedores Online, Fingerprint e Extras** — cliente HTTP único (token bucket por host, cache, User-Agent, backoff), MusicBrainz/CAA/AcoustID, Chromaprint dylib, modo offline padrão com consentimento, dedup semântico, duplicatas por fingerprint, importador `.wsz` (spike), visualizações extras. *Pesquisa de fase.*

**Pesquisa de fase:** 2, 3, 6, 7, 8. **Padrões estabelecidos (pular):** 1 (só spike de `swift test`), 4, 5.

## Avaliação de Confiança

| Área | Confiança | Notas |
|---|---|---|
| Stack | MÉDIA-ALTA | GRDB, ZIPFoundation, SFB conferidos no GitHub; APIs Apple por conhecimento prévio; Chromaprint e `swift test` não verificados |
| Features | MÉDIA | Domínio + briefing, sem web |
| Arquitetura | MÉDIA | Código atual lido por inteiro; referências só na estrutura |
| Pitfalls | MÉDIA | Coerente com o grafo real do SFB e o `build-app.sh`; termos externos em BAIXA |

### Itens [VERIFICAR] em aberto
1. `swift test` só com CLT (Swift Testing roda? plano B). (Fase 1)
2. GRDB 7.11.1 compila com CLT e tools 5.9. (Fases 1/2)
3. Tap no mixer/pós-EQ conta como modificar o grafo no SFB 0.14? Sobrevive a `reconfigureProcessingGraph`? (Fase 3)
4. Pan do mixer basta ou precisa de mixer dedicado? Testar mono. (Fase 3)
5. Ordem e religação timePitch → EQ → pan. (Fase 3)
6. `currentTime` do SFB considera a taxa? Impacto em `.lrc`, Now Playing, progresso. (Fases 3–4)
7. Gapless com EQ inserido; `iTunSMPB`/LAME header. (Fase 3)
8. Cobertura de `writeMetadata` por formato (frames desconhecidos, padding, versão ID3, tipo da capa). (Fase 2)
9. `replaceItemAt` e xattrs/datas/inode — impacto na detecção de arquivo movido. (Fase 2)
10. Backup por `clonefile` em volume externo não-APFS: fallback e espaço. (Fase 2)
11. Confirmar "sem sandbox" e formato de `LibraryRoot`/bookmark. (Fase 2)
12. Chromaprint: build com CLT, versão e licença, KissFFT vs vDSP. (Fase 8)
13. Termos de MusicBrainz, AcoustID, CAA, LRCLIB para app público. (Fase 8)
14. `notarytool`/`stapler` nos CLT; certificado Developer ID e conta paga. (Fases 1 e 6)
15. Frameworks LGPL com o mesmo Team ID vs `disable-library-validation`. (Fase 6)
16. MPRemoteCommandCenter e teclas físicas em `.app` montado por script. (Fase 6)
17. Formato `.eqf` e escopo realista do `.wsz`. (Fases 5/8)
18. Comportamento em macOS 14/15 (ambiente é macOS 27); testar na VM tart. (Fases 1 e 6)

### Lacunas
- Valor visível tardio: critério de aceite ponta a ponta por fase.
- Pesos de confiança do Fixer: calibrar com corpus real.
- Single/EP sem MusicBrainz: rotular `inferred`, nunca presumir single em `unknown`.
- Escala: teste com biblioteca sintética de 100 mil arquivos na fase 2.
- Sem Instruments: `os_signpost`, `sample`, `leaks`, `vmmap`, render offline.

## Fontes
- **ALTA:** código local, `.build/checkouts/SFBAudioEngine`, releases GitHub (GRDB 7.11.1, ZIPFoundation 0.9.20, SFBAudioEngine 0.14.0, chromaprint v1.6.2), ambiente local (Swift 6.4, `Testing.framework` nos CLT), PROJECT.md e briefing.
- **MÉDIA:** estrutura/schema do Mixxx, módulos de Cog e Audacious; conhecimento de Picard, OneTagger, foobar2000, Swinsian, Doppler, Vox.
- **BAIXA (validar):** APIs Apple, formatos de tag, sandbox/notarização, termos de provedores, `swift test` nos CLT.

---
*Pesquisa concluída: 2026-10-19; síntese: 2026-10-20 — Pronto para o roadmap: sim*
