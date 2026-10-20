# Arquitetura

**Domínio:** player de música nativo macOS com biblioteca persistente e assistente de correção de tags (Library Fixer)
**Pesquisado em:** 2026-10-19
**Confiança geral:** MÉDIA (código atual lido; Mixxx/Cog/Audacious inspecionados só na estrutura de diretórios e no schema do Mixxx; GRDB e regras de concorrência do Swift vêm de conhecimento prévio, não verificados via Context7 nesta rodada)

## Diagnóstico do código atual

- Alvo único executável `Wineup` (~1400 linhas). `PlayerState` (ObservableObject, 192 linhas) mistura: lista de faixas, transporte, fila, EQ, estado de UI (query, filtro, escala de letras), carregamento de capa/letras e `DispatchQueue` manual.
- `Track` tem `id: Int` (índice efêmero), `url` opcional, e mistura dado de domínio com `MarkColor: Color` (SwiftUI). Não há como persistir nem separar arquivo de gravação.
- `AudioEngineService` já isola bem o SFBAudioEngine, mas expõe `currentTime` por polling (`tick`) e não tem tap de medição. Bom ponto de partida: só precisa virar um protocolo.
- Não há alvo de teste. Um alvo `executableTarget` não pode ser importado por testes em SwiftPM de forma estável, então a extração de uma biblioteca é pré-requisito para qualquer teste.

## Arquitetura recomendada

Camadas horizontais (decisão do usuário), com dependência estritamente de cima para baixo. Cada camada é um target SwiftPM; só a última é executável.

```
┌──────────────────────────────────────────────────────────┐
│ Wineup (executável)  App + composição (wiring)           │
│   WineupApp, AppEnvironment, menus, MediaKeys/NowPlaying │
├──────────────────────────────────────────────────────────┤
│ WineupUI (SwiftUI)   Panels, Components, Layout, Skins   │
│   ViewModels @MainActor (@Observable), SkinEngine        │
├──────────────────────────────────────────────────────────┤
│ WineupServices       Orquestração (sem UI)               │
│   PlaybackController, QueueManager, LibraryScanner,      │
│   FixerPipeline, ArtworkResolver, LyricsService          │
├───────────────────────────┬──────────────────────────────┤
│ WineupAudio               │ WineupLibrary                │
│  AudioEngine (protocolo)  │  Database (SQLite), Schema,  │
│  SFBAudioEngine adapter   │  Repositories, Migrations,   │
│  EQ, Meter, Spectrum      │  TagReader/TagWriter (SFB)   │
├───────────────────────────┴──────────────────────────────┤
│ WineupCore  (Foundation puro, sem SFB/SwiftUI/AppKit)    │
│   Modelos de domínio, IDs, protocolos (portas), Confiança│
│   Diff de tags, Journal (tipos), erros                   │
└──────────────────────────────────────────────────────────┘
```

Regra de dependência: `Core` não importa nada do projeto. `Audio` e `Library` só importam `Core` (e nunca um ao outro). `Services` importa `Core` e as portas de `Audio`/`Library`. `UI` importa `Services`+`Core`, nunca `Library` nem `Audio` diretamente. O executável é o único lugar que instancia implementações concretas (composição).

Observação: esta é a forma "camadas horizontais" mas com portas (protocolos) em `Core`, para que `Services` seja testável com falsos (fakes) sem SQLite nem áudio.

### Limites dos componentes

| Componente (target) | Responsabilidade | Fala com |
|---|---|---|
| WineupCore | Entidades (`AudioFile`, `Recording`, `Release`, `ReleaseTrack`, `Artist`, `Artwork`, `Lyrics`, `Playlist`), `Confidence`, `TagSet`, `TagDiff`, `JournalEntry`, protocolos `AudioEngine`, `LibraryStore`, `TagIO`, `MetadataProvider` | ninguém (folha) |
| WineupAudio | Implementa `AudioEngine` com SFBAudioEngine + AVAudioEngine; EQ, medidor, espectro, velocidade, balanço; publica snapshots de medição | Core |
| WineupLibrary | SQLite (GRDB), migrações, repositórios, consultas de navegação/busca (FTS5), leitura/gravação de tags via SFB (`TagIO`), journal em disco | Core |
| WineupServices | `PlaybackController` (fila + transporte + dedup single↔álbum), `LibraryScanner`, `FixerPipeline`, `ArtworkResolver`, `LyricsService`, `NowPlayingBridge` (porta) | Core + portas |
| WineupUI | Views, ViewModels `@MainActor`, `SkinEngine`/`Theme` | Services, Core |
| Wineup (exe) | `AppEnvironment` monta tudo; MPRemoteCommandCenter/NowPlaying; atalhos; janelas | todos |

Testes: `WineupCoreTests`, `WineupLibraryTests` (SQLite em memória), `WineupServicesTests` (fakes), `WineupAudioTests` (só o que não exige dispositivo: curvas de EQ, matemática de medidor). Nota: com Command Line Tools sem Xcode, `swift test` com XCTest pode não estar disponível; validar cedo se Swift Testing/XCTest rodam (ver Lacunas).

## Fluxo de dados

Direção: dados fluem para cima como snapshots imutáveis; comandos fluem para baixo.

```
Disco ──scan──▶ LibraryScanner ──upsert──▶ SQLite ──observação──▶ ViewModels ──▶ Views
                                                   ▲
Views ──intent──▶ ViewModel ──▶ PlaybackController ──▶ AudioEngine ──(tap)──▶ MeterSnapshot ──▶ UI
```

- UI lê de ViewModels `@MainActor` que assinam `AsyncStream`/observação do GRDB (ValueObservation). Nunca consulta o banco no corpo de `body`.
- Transporte: UI chama `PlaybackController`; este chama `AudioEngine`. Eventos do motor (fim de faixa, erro, formato mudou) voltam como `AsyncStream<EngineEvent>`, não por closures chamadas fora da main.
- Progresso: em vez de `tick` por timer lendo `currentTime`, o controller publica `PlaybackClock` (posição + horário de referência) e a UI interpola com `TimelineView`. Reduz trabalho e remove a divergência de `progress` fracionário.

## Modelo de áudio e threading

- **Thread de render é intocável.** Nada de alocação, locks, `print`, Swift `async` ou ARC pesado dentro de tap/render. Medidores usam `installTap` do `AVAudioMixerNode`/nó pós-EQ (o tap roda numa fila interna da Apple, não no render RT, mas ainda deve ser barato) e calculam RMS/pico; o resultado é escrito em uma estrutura atômica ou ring buffer e lido pela UI a ~30-60 Hz.
- **Espectro:** tap com buffer 1024-2048, FFT com Accelerate (`vDSP`), janela de Hann, 20-32 bandas log; processa numa fila serial própria (`DispatchQueue` utility), publica `[Float]` imutável. Sem trabalho na main além de desenhar.
- **Grafo:** manter o padrão atual (SFB `sourceNode` → EQ → `mainMixerNode`), alterações só via `modifyProcessingGraph`, e refazer a ligação no callback `reconfigureProcessingGraph` quando o formato mudar. Velocidade: `AVAudioUnitTimePitch` (rate, pitch preservado) no mesmo trecho, na ordem sourceNode → timePitch → EQ → mixer. Balanço: `pan` do mixer (confirmar que `mainMixerNode.pan` basta; senão `AVAudioUnitEQ`/mixer dedicado).
- **ReplayGain não destrutivo:** ganho aplicado como volume do nó (não regrava amostras); valores lidos pelo `TagIO` e guardados no banco, nunca derivados em tempo de reprodução do arquivo.
- **Isolamento Swift:** `AudioEngine` é um `actor`-like fachada: métodos chamados da main, mas estado mutável do `AVAudioEngine` protegido por uma fila serial. Callbacks do delegate do SFB (fora da main) viram `AsyncStream` e são consumidos no controller.
- **Gapless/pré-carga:** SFB `AudioPlayer` suporta `enqueue`; o controller deve pré-enfileirar a próxima faixa (prevista pela fila) para reprodução sem pausa. Tratar como fase de áudio, não de UI.
- **Referências (só ler):** Cog separa `AudioDecoder`/`AudioMetadataReader`/`AudioMetadataWriter`/`AudioPropertiesReader`/`AudioPlayer` (fronteiras decoder x tag x player são distintas); Audacious separa `libaudcore` (playlist, tuplas, scanner) de `libaudgui/libaudqt` (UI) e `libaudtag` (tags) — mesma ideia das camadas acima.

## Esquema do banco (SQLite via GRDB)

Referência: o schema do Mixxx (`track_locations` separado de `library`, `LibraryHashes` por diretório para varredura incremental, `Playlists`/`PlaylistTracks`, `cues`, `track_analysis`) confirma duas escolhas: separar localização física da faixa lógica e usar hash por diretório para detectar mudanças. Não copiar; apenas o conceito.

Tabelas (todas com `id INTEGER PRIMARY KEY` + `uuid` estável para journal/exportação):

| Tabela | Campos principais | Observações |
|---|---|---|
| `audio_file` | path, bookmark (Data), size, mtime, content_hash, codec, sample_rate, bit_depth, duration, status (`present`/`missing`), recording_id? | Fato físico. Caminho muda → mesmo `content_hash`/`file_id` reencontra. `recording_id` nulo até resolver |
| `recording` | title, duration, mbid?, acoustid?, isrc?, fingerprint? | Gravação lógica; várias `audio_file` podem apontar a ela (cópias) |
| `release` | title, type (`album`/`single`/`ep`/`compilation`/`unknown`), type_source (`tag`/`inferred`/`user`), year, mbid?, album_artist_id | `unknown` nunca é presumido single. "Singles" é consulta/visão, não valor gravado |
| `release_track` | release_id, recording_id, disc, position | Mesmo `recording` pode estar em single e álbum (base da dedup na fila) |
| `artist` | name, sort_name, mbid? | |
| `recording_artist` / `release_artist` | role, ordem | N:N |
| `artwork` | kind (`embedded`/`sidecar`/`release`/`provider`/`placeholder`), file_id?/release_id?, blob_hash, width, height, source, confidence | Capa do arquivo ≠ capa do lançamento (fallback visual sem gravar). Cache de miniaturas em disco por hash, fora do SQLite |
| `lyrics` | recording_id, kind (`embedded`/`lrc`/`provider`), text, synced (bool), source, confidence | |
| `tag_snapshot` | file_id, json das tags lidas, read_at | Base para diff do Fixer e para `Dirty` detection |
| `playlist`, `playlist_item` | ordem, recording_id ou file_id | Itens por `recording` quando possível, para sobreviver a caminhos que mudam |
| `queue_state` | serializado | Restaura sessão |
| `fixer_run`, `fixer_issue`, `fixer_change` | run_id, issue_type, confidence, status, before/after JSON | Persistência do diagnóstico e da prévia |
| `journal` | run_id, file_id, op (`tag_write`/`rename`/`move`/`artwork_embed`), before, after, backup_path, applied_at, undone_at | Fonte da verdade do desfazer |
| `scan_dir` | path, bookmark, dir_hash, last_scan | Varredura incremental (conceito do `LibraryHashes`) |
| `setting` | k, v | EQ presets, skin ativa etc. |

Índices: `audio_file(path)`, `audio_file(content_hash)`, FTS5 sobre título/artista/álbum para a busca. Migrações versionadas no GRDB (`DatabaseMigrator`), nunca editar migração já lançada. Recomendação: GRDB (MIT, SwiftPM puro, observação reativa). Alternativa: SQLite.swift. SQLite direto via C API só se GRDB falhar no build com CLT.

Importante para o sandbox/permissão: guardar *security-scoped bookmarks* por pasta raiz se o app for assinado com sandbox; hoje é ad-hoc sem sandbox, mas decidir antes de notarizar, pois mudar depois quebra caminhos salvos.

## Pipeline de varredura

1. **Enumerar** (`FileManager` `enumerator` com `URLResourceKey`s: tamanho, mtime, isDirectory) por `scan_dir`.
2. **Comparar** com `audio_file` (path + size + mtime). Só arquivos novos/alterados avançam; diretórios inalterados (dir_hash) são pulados.
3. **Ler** tags + propriedades via `TagIO` (SFB) em `TaskGroup` com concorrência limitada (≈ núcleos), em lote de ~200 por transação.
4. **Resolver identidade:** agrupar em `recording`/`release`/`artist` por regras determinísticas (IDs de tag se existirem, senão normalização de nome + duração). Sem tag de álbum → `release.type = unknown`.
5. **Gravar** upserts numa transação; marcar ausentes como `missing` (não apagar). Reconhecer movidos por `content_hash`/(size+duração+tags).
6. **Capa:** só registra existência/metadado; miniaturas geradas sob demanda e cacheadas.
7. Progresso e cancelamento: `AsyncStream<ScanProgress>` + `Task` cancelável; a varredura nunca bloqueia reprodução.

## Pipeline do Library Fixer

Cinco estágios, cada um com função pura sobre dados do banco onde possível; só o último toca arquivos.

```
Diagnose ──▶ Propose ──▶ Preview ──▶ Apply ──▶ Journal/Undo
 (leitura)   (leitura/    (UI, edição   (escrita   (reverter)
             rede opcional) seletiva)    atômica)
```

1. **Diagnose** (somente leitura, offline): regras (`Rule` protocol) sobre `tag_snapshot`/`audio_file` geram `fixer_issue` (tag ausente, inconsistência de artista/álbum entre faixas do mesmo release, capa ausente/minúscula, letra sem .lrc, candidatas a duplicata). Nenhum I/O de rede.
2. **Propose:** cada issue vira `fixer_change` com `before`, `after`, `source` e `Confidence` (0-1 + rótulo + razão textual). Provedores externos (MusicBrainz/AcoustID) entram só atrás da porta `MetadataProvider`, opt-in, com aviso do que é enviado; retorno tratado como dado não confiável (validar/sanitizar, limitar tamanho). Regra dura: proposta de baixa confiança nunca sobrescreve campo já preenchido sem aceite explícito.
3. **Preview:** UI mostra diff por arquivo, origem, confiança; aceitar tudo / seletivo / manual / ignorar (ignorados persistem).
4. **Apply:** por arquivo: (a) revalidar `mtime/hash` — se mudou desde o diagnóstico, abortar o item; (b) copiar backup para a pasta de backup do app; (c) gravar tag em arquivo temporário e substituir atomicamente (`replaceItemAt`) ou gravar via SFB e reler para verificar; (d) escrever `journal` na mesma transação lógica; (e) atualizar `tag_snapshot`. Tags, renomeação e áudio são operações separadas e com consentimentos separados. Nunca alterar amostras.
5. **Undo:** inverte `journal` em ordem reversa a partir do backup/`before`; falha parcial não apaga o journal.

Atenção: a gravação de tags é onde mora o risco ao "Core Value". Esse estágio deve ficar atrás de um único tipo (`TagWriter`) com testes sobre cópias de arquivos de exemplo e um modo `dryRun`.

## Skins / temas

- Hoje `Theme` é um enum de 3 temas em código. Evoluir para dado: `SkinManifest` (JSON/plist em `WineupCore`) com paleta, métricas, fontes, nomes de assets e disposição de painéis; `SkinEngine` (UI) injeta via `Environment`.
- Separar **tema** (cores/tipografia aplicadas a componentes SwiftUI) de **skin bitmap** (imagens posicionadas). Primeiro entregar tema declarativo (formato próprio documentado); skin `.wsz` é um *importador* separado (zip de bitmaps + `main.txt`/`region.txt`) que converte para `SkinManifest` e deve ser spike com escopo explícito, não requisito de arquitetura.
- Componentes (`ChromeButton`, `Panel`, `ChromeSlider`) consomem apenas tokens do tema, nunca cores literais.
- `MarkColor` sai de `Track` (domínio) e vai para UI; no domínio vira `Mark` sem `Color`.

## Padrões a seguir

### Portas em Core, adaptadores nas camadas

```swift
public protocol AudioEngine: Sendable {
    func load(_ url: URL, startingAt: TimeInterval) async throws
    func play() async; func pause() async; func stop() async
    func seek(to: TimeInterval) async
    var events: AsyncStream<EngineEvent> { get }
    var meter: AsyncStream<MeterSnapshot> { get }   // amostrado, nunca por buffer
}
```

### Snapshots imutáveis para a UI
ViewModels expõem `struct`s (`TrackRowModel`) e não entidades do banco; consistente com a regra de imutabilidade do usuário.

### Estado dividido do `PlayerState`
`PlaybackViewModel` (transporte/progresso), `QueueViewModel`, `LibraryViewModel` (navegação/busca), `EqualizerViewModel`, `LayoutPrefs`. Migrar com `@Observable` (macOS 14 já suportado) para evitar invalidação de toda a árvore a cada tick.

## Anti-padrões a evitar

- **Objeto-deus (`PlayerState`):** continua crescendo e arrasta SwiftUI/AppKit para o domínio. Dividir antes de adicionar fila/biblioteca.
- **ID por índice (`Track.id: Int`):** inviabiliza persistência; usar UUID/rowid estáveis.
- **Biblioteca derivada da lista de reprodução:** a biblioteca é do banco; a fila referencia a biblioteca.
- **Gravar tags no meio da varredura ou da reprodução:** só o Fixer grava, com journal.
- **Sobrescrever Album para criar "Singles":** é visão virtual por consulta.
- **Consulta ao banco/IO em `body` de View ou na thread de áudio.**
- **Timer de 30 Hz alterando `@Published` grande:** invalida a UI inteira.
- **Dependência circular via `AppEnvironment` global:** injetar por inicializador.

## Ordem de construção (camadas horizontais)

Dependências guiam a ordem; cada degrau termina com build demonstrável e testes.

1. **Fundação e extração (Core + estrutura de pacote).** Criar `WineupCore`, mover `Track`→modelos de domínio, definir protocolos. Converter o executável em `Wineup` fino sobre bibliotecas; adicionar alvos de teste e validar que `swift test` roda com CLT. App continua tocando como hoje. (Pré-requisito de tudo; pequeno e arriscado só se o teste não rodar sem Xcode.)
2. **Dados (Library).** Schema + migrações + repositórios + `TagIO` (leitura) + scanner incremental + busca FTS. Testes com SQLite em memória e fixtures de áudio. Depende de 1. Entrega: biblioteca persistente, restauração entre sessões, ainda com UI antiga lendo via adaptador.
3. **Áudio (Audio).** Extrair `AudioEngine` como porta; adicionar medidor/espectro reais, velocidade, balanço, ReplayGain, pré-carga/gapless, eventos por `AsyncStream`. Pode correr em paralelo com 2 (independentes), mas só depois de 1.
4. **Serviços.** `PlaybackController` + fila/repetir/embaralhar/dedup, playlists salvas, `NowPlayingBridge`, `ArtworkResolver` (fallbacks), letras .lrc. Depende de 2 e 3.
5. **UI.** Dividir `PlayerState` em ViewModels; navegação artista/álbum/single; painéis ligados a medidores reais; `SkinEngine` declarativo. Depende de 4.
6. **Wiring.** `AppEnvironment`, controles de mídia do sistema, atalhos, janelas, persistência de layout; empacotamento/assinatura (`scripts/build-app.sh`). Depende de 5.
7. **Fixer (vertical sobre as camadas já prontas).** Diagnose → Propose (local) → Preview → Apply → Undo, com `TagWriter` e journal. Só começa quando 2 (snapshot, hash) e 4 estão estáveis. Provedores/fingerprint e importador `.wsz` por último, como extensões atrás de portas.

Observação sobre o modelo "camadas horizontais": entregar dados, áudio e UI em degraus separados adia valor visível e esconde o desencaixe entre camadas. Mitigação: manter sempre um caminho de ponta a ponta mínimo (tocar arquivo do banco) ao fim do degrau 4 e usar o app real como teste de integração.

## Escalabilidade

| Preocupação | 5 mil faixas | 50 mil | 500 mil |
|---|---|---|---|
| Varredura inicial | tudo em lote, segundos a minutos | lotes + concorrência limitada, progresso | incremental por `dir_hash`, retomável |
| Lista na UI | `List` direto | `LazyVStack`/`Table` com paginação por consulta | consultas com janela (`LIMIT/OFFSET` ou keyset) e FTS |
| Capas | cache em memória | cache em disco por hash, miniaturas | miniaturas pré-geradas em segundo plano |
| Banco | 1 conexão | pool de leitores (WAL) | WAL + índices revisados, `VACUUM` ocasional |

## Fontes

- Código atual em `Sources/Wineup` (lido integralmente: `AudioEngineService`, `PlayerState`, `Track`, `Package.swift`) — ALTA
- Briefing `wineup-player.md` (seções Modelo de dados, Fixer, Capas, Álbuns) — ALTA
- Mixxx `res/schema.xml` e `src/library` (apenas estrutura de tabelas e diretórios, como dado) — MÉDIA
- Cog `Audio/` e Audacious `src/` (apenas nomes de módulos/diretórios) — MÉDIA
- GRDB, FTS5, `AVAudioUnitTimePitch`, regras de tap/threading, `replaceItemAt` — conhecimento prévio, NÃO verificado nesta rodada — BAIXA/MÉDIA

## Lacunas para pesquisa de fase

- `swift test` (XCTest ou Swift Testing) funciona só com Command Line Tools? Validar no degrau 1.
- GRDB resolve e compila via SwiftPM com CLT, sem Xcode? Validar antes de fixar a escolha.
- API exata do SFB (versão 0.14+) para escrita de tags e ReplayGain, e comportamento de `enqueue`/gapless com o EQ inserido.
- `mainMixerNode.pan` realmente afeta saída estéreo no grafo do SFB; ordem TimePitch/EQ.
- Sandbox vs. sem sandbox (bookmarks) antes da notarização.
- Viabilidade e licença de importar `.wsz` (spike).
