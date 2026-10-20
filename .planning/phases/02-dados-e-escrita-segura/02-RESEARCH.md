# Phase 2: Dados e Escrita Segura - Pesquisa

**Pesquisado:** 2026-10-20
**Domínio:** persistência SQLite (GRDB), varredura incremental, escrita segura de tags (SFBAudioEngine/TagLib), APFS
**Confiança:** ALTA nos resultados experimentais; MÉDIA nas recomendações de arquitetura

## Resumo

Tudo foi medido numa cópia descartável do projeto (APFS `cp -c`), depois apagada. O `Package.swift` real não foi alterado. Resultados principais:

1. **GRDB 7.11.1 resolve e compila só com CLT**, mesmo com o pacote raiz em `swift-tools-version: 5.9` (o GRDB declara tools 6.1; basta o toolchain ser >= 6.1, aqui Swift 6.4). O SQLite do sistema é o 3.54.0 com `ENABLE_FTS5`. `unicode61 remove_diacritics 2` funciona (`beyonce` acha "Beyoncé", `ros` acha "Rós"). `DatabasePool` entra em WAL.
2. **Achado crítico para SAFE-03: `AudioFile.writeMetadata()` do SFB NÃO satisfaz SAFE-03 para MP3 e WAV.** Medido: (a) um MP3 ID3v2.3 vira ID3v2.4 após gravar; (b) a data de lançamento é APAGADA (o frame TDRC/TYER é removido porque o SFB faz `NSISO8601DateFormatter.dateFromString` com opções padrão, que só aceitam timestamp completo; "2019" ou "2020-05-01" viram nil); (c) um rodapé ID3v1 de 128 bytes é criado onde não existia. FLAC, M4A/ALAC, Ogg Opus e Ogg Vorbis preservam campos desconhecidos e capas. **Recomendação:** `TagWriter` com um protocolo `TagBackend`; FLAC/M4A/Opus/Vorbis usam o SFB; MP3 e WAV (ID3v2) usam um pequeno alvo ObjC++ sobre TagLib (já resolvido como dependência do SFB, produto `taglib` do `CXXTagLib`), que foi provado preservar versão, data e sem rodapé ID3v1. Isto precisa de confirmação do usuário (ver Suposições/Perguntas), pois a decisão do CONTEXT diz "via SFBAudioEngine writeMetadata".
3. Fixtures: **todos os formatos podem ser gerados localmente**. `afconvert` faz WAV/FLAC/M4A(AAC)/ALAC; **não** faz MP3 nem Ogg. MP3, Ogg Opus e Ogg Vorbis saem de `AudioConverter.convert(src, to: dst.mp3|.opus|.ogg)` do próprio SFB (LAME/libopus/libvorbis embutidos). Unidade de 1 s estéreo: 8–40 KB cada.
4. APFS: `clonefile` é instantâneo e sem custo de espaço; falha com `ENOTSUP` (45) em HFS+ e `EXDEV` (18) entre volumes. `replaceItemAt` **troca o inode** mas **preserva xattrs** do original. Renomear/mover no mesmo volume **mantém** o inode.
5. Escala: 100 mil linhas + FTS5 inseridas em 1,3 s; busca por prefixo 1–30 ms; enumeração de 100 mil arquivos 0,10–0,36 s (cache quente). O gargalo real é ler tags (SFB ~0,15 ms/arquivo pequeno, mais com capas grandes).

**Recomendação principal:** implementar o `TagWriter` em torno de um fluxo único backup → cópia de trabalho → gravar → reler/verificar (inclusive campos NÃO alterados e data) → `replaceItemAt` → atualizar `audio_file` (inode/mtime/size) e journal na mesma transação; usar o verificador "snapshot antes/depois" como rede de segurança contra perdas silenciosas do backend.

<user_constraints>
## User Constraints (de CONTEXT.md)

### Decisões travadas
- Novo target SwiftPM `WineupLibrary` (depende de `WineupCore`, GRDB e SFBAudioEngine) + `WineupLibraryTests`. Dependência nova: GRDB.swift 7.x (MIT) — validar que resolve/compila só com CLT.
- SQLite via GRDB `DatabasePool` (WAL), migrations numeradas desde a v1, FTS5 com `unicode61 remove_diacritics 2`.
- Esquema separando: `library_root`, `audio_file` (caminho, inode/file ID, tamanho, mtime, `content_hash` opcional, `status` present/missing), `recording`, `release` (tipo com origem tag/inferred/user; `unknown` nunca vira single), `release_track`, `artist`, `artwork`, `lyrics`, `tag_snapshot`, `journal`. Itens ausentes são marcados `missing`, nunca apagados.
- Sem sandbox; acesso a pastas atrás de `LibraryRoot` (já no WineupCore). Banco em `~/Library/Application Support/Wineup/library.sqlite`.
- Scanner incremental em duas etapas (enumeração rápida por tamanho+mtime+inode; leitura de tags só do que mudou), em lotes de transação, com progresso (AsyncStream) e cancelamento (Task cancellation).
- Escrita segura: um único `TagWriter` no WineupLibrary; fluxo: backup (clonefile no mesmo volume; fallback cópia em Application Support/Wineup/Backups) → gravar numa cópia de trabalho via SFBAudioEngine `writeMetadata` → reler e verificar (tags esperadas + duração) → `FileManager.replaceItemAt` → registrar no journal; `undo(journalEntry)` restaura o backup. `dryRun` retorna o diff sem tocar no arquivo.
- Fixtures de teste geradas em diretório temporário (afconvert a partir de WAV gerado), nunca commitadas como áudio grande; MP3 só se houver encoder disponível (SFB inclui LAME) — documentar o que não for possível testar.
- Teste de escala LIB-07 com biblioteca sintética de 100 mil entradas: o disco do usuário está ~98% cheio, então usar arquivos vazios/minúsculos ou inserir registros sintéticos direto no banco; limpar ao final. Não criar GBs de dados.
- Integração mínima com o app: o painel Playlist/Search pode ler da biblioteca persistida via adaptador simples (sem refatorar a UI — isso é Fase 5); ⌘O/arrastar adicionam raízes à biblioteca.
- Gate de cada plano: `./scripts/test.sh` + `swift build -c release`; ao final da fase `./scripts/build-app.sh` (testes + empacotamento + smoke).

### Critério do Claude (discricionário)
Demais escolhas a critério do pesquisador/planejador, guiadas pelos critérios de sucesso do ROADMAP.

### Ideias adiadas (FORA DE ESCOPO)
UI de edição de tags (Fase 7), navegação de discografia na UI (Fase 5), fila/playlists (Fase 4).
</user_constraints>

<phase_requirements>
## Requisitos da fase

| ID | Descrição | Apoio da pesquisa |
|----|-----------|-------------------|
| LIB-01 | Pastas-raiz persistem entre sessões | tabela `library_root`; GRDB DatabasePool; caminho em Application Support |
| LIB-02 | Varredura incremental com progresso e cancelamento | enumeração em duas etapas; benchmarks de enumeração; AsyncStream |
| LIB-03 | Movido/renomeado/desconectado vira ausente sem perder playlists/histórico | inode estável em rename; status `missing`; identidade (volume UUID + inode) |
| LIB-04 | Busca ignorando acentos, instantânea | FTS5 `remove_diacritics 2` verificado; 1–30 ms em 100k |
| LIB-05 | Navegar por artista/álbum/gênero/pasta/todas | consultas GROUP BY sobre índices; sem custo especial |
| LIB-06 | Modelo distingue arquivo/gravação/faixa-no-lançamento/lançamento/artista/arte/letra | esquema da seção Arquitetura |
| LIB-07 | 100 mil arquivos varridos e pesquisados sem travar | benchmarks; progresso em lotes; leituras em pool |
| SAFE-01 | Único gravador: backup, verificação, diário | fluxo TagWriter; armadilhas de MP3/WAV |
| SAFE-02 | Desfazer a partir do diário | backup via clonefile/cópia; restauração com replaceItemAt; atualizar inode |
| SAFE-03 | Preservar campos desconhecidos, versão ID3 e capas em FLAC/MP3/M4A/Opus/WAV | matriz por formato abaixo (MP3/WAV exigem TagLib direto) |
</phase_requirements>

## Mapa de responsabilidade arquitetural

App desktop sem servidor; as "camadas" são módulos SwiftPM.

| Capacidade | Dono principal | Secundário | Justificativa |
|------------|---------------|-----------|---------------|
| Contratos/valores puros (Track, TagDiff, JournalEntry, LibraryRoot, Confidence) | WineupCore | — | Foundation puro, testável sem UI |
| Persistência, migrations, FTS, scanner | WineupLibrary | — | Depende de GRDB/SFB; ficam fora do core |
| Leitura de tags/propriedades | WineupLibrary (adaptador SFB) | — | Hoje existe `TrackLoader` no target app; a biblioteca precisa do seu próprio leitor sem NSImage |
| Escrita de tags | WineupLibrary `TagWriter` + backends | Alvo ObjC++ TagLib (MP3/WAV) | Ponto único exigido por SAFE-01 |
| Backup/journal | WineupLibrary | Sistema de arquivos | clonefile/copyItem + tabela `journal` |
| UI/adaptador de busca | Wineup (app) | — | Apenas adaptador; refatoração é Fase 5 |

## Stack padrão

### Núcleo
| Biblioteca | Versão | Propósito | Por que |
|-----------|--------|-----------|---------|
| GRDB.swift | 7.11.1 (último release; resolve com `from: "7.0.0"`) [VERIFIED: github releases API + build local] | SQLite, DatabasePool/WAL, migrator, FTS5 | Builds com CLT; usa SQLite do sistema 3.54.0 com FTS5 [VERIFIED: PRAGMA compile_options] |
| SFBAudioEngine | 0.14.0 (já no projeto) | Leitura de tags/propriedades, escrita FLAC/M4A/Ogg, encoders p/ fixtures | já resolvido |
| CXXTagLib (produto `taglib`) | >= 2.3.2 (já resolvido como dep do SFB) [VERIFIED: .build/checkouts] | Escrita ID3v2 exata (MP3/WAV) | ver pitfalls; precisa de um alvo ObjC++ próprio |

### Alternativas consideradas
| Em vez de | Poderia usar | Tradeoff |
|-----------|-------------|----------|
| Alvo TagLib p/ MP3/WAV | Só SFB `writeMetadata` | Mais simples, mas perde data, sobe ID3 para 2.4 e cria ID3v1; reprova SAFE-03 |
| GRDB | SQLite.swift / API C direta | GRDB já escolhido (decisão travada) |

**Instalação (Package.swift, planejar na Wave 1):**
```swift
.package(url: "https://github.com/groue/GRDB.swift", from: "7.0.0"),
// só se a decisão do usuário for TagLib direto:
.package(url: "https://github.com/sbooth/CXXTagLib", from: "2.3.2"),
// targets:
.target(name: "WineupLibrary",
        dependencies: ["WineupCore",
                       .product(name: "GRDB", package: "GRDB.swift"),
                       .product(name: "SFBAudioEngine", package: "SFBAudioEngine"),
                       "WineupID3"],            // ObjC++ opcional
        path: "Sources/WineupLibrary",
        swiftSettings: [.unsafeFlags(["-strict-concurrency=complete"])]),
.target(name: "WineupID3", dependencies: [.product(name: "taglib", package: "CXXTagLib")], path: "Sources/WineupID3"),
.testTarget(name: "WineupLibraryTests", dependencies: ["WineupLibrary"], path: "Tests/WineupLibraryTests"),
```
Verificado: um alvo `.target` ObjC++ (`.mm` + `include/Shim.h`) dependendo de `taglib` compila com CLT. O header público precisa de `extern "C"` sob `#ifdef __cplusplus` (sem isso, "Undefined symbols" no link, pois o nome sai com mangling C++) [VERIFIED: experimento]. O app (`Wineup`) deve depender de `WineupLibrary`; `build-app.sh` já copia `*.framework` — conferir se o novo alvo estático não exige nada extra.

## Padrões de arquitetura

### Diagrama de fluxo
```
Usuário adiciona pasta (⌘O/arrastar) -> LibraryRoot -> library_root (SQLite)
        |
        v
Scanner.scan(root) --Etapa 1: enumeração rápida (fts(3) ou FileManager.enumerator)-->
   compara (path,size,mtime,inode) com audio_file em memória (mapa carregado em 0,07 s p/ 100k)
        |-- inalterado: só marca last_seen
        |-- novo/alterado: fila --> Etapa 2: leitura SFB (properties+metadata) em lotes de ~500-1000 por transação
        |-- sumiu: inode igual em outro caminho? -> atualiza path (movido); senão status=missing (nunca DELETE)
        '-- progresso via AsyncStream<ScanProgress>; Task.checkCancellation() entre lotes
        v
audio_file / recording / release / release_track / artist / artwork / lyrics  --triggers/rebuild-->  audio_fts (FTS5 external content)
        |
UI/adaptador: SELECT ... MATCH 'termo*' (DatabasePool.read, fora da main)

Escrita de tag: TagWriter.write(url, changes, dryRun)
   snapshot_before (leitura completa) -> dryRun? retorna [TagDiff]
   -> backup (clonefile; EXDEV/ENOTSUP -> copyItem p/ Application Support/Wineup/Backups)
   -> cópia de trabalho (clonefile no mesmo dir, nome oculto) -> backend.write(cópia)
   -> reler cópia: snapshot_after; verificar (alterados = esperados; NÃO alterados = iguais; duração ~igual; ID3 version/imagens)
   -> replaceItemAt(original, cópia) -> stat novo (inode/mtime/size) 
   -> transação única: audio_file atualizado + tag_snapshot + journal(entry, backup_path, diffs)
undo(entry): verificar que arquivo atual == pós-gravação (hash/size/mtime), restaurar backup via replaceItemAt, atualizar audio_file, journal marca revertido.
```

### Estrutura recomendada
```
Sources/WineupLibrary/
  Database/   (DatabaseManager, Migrations, Records)
  Scanner/    (Enumerator, ScanPlanner, TagReader, Scanner)
  Search/     (SearchService, FTS helpers)
  Safety/     (TagWriter, TagBackend, SFBBackend, ID3Backend, BackupStore, Journal, TagSnapshot)
Sources/WineupID3/   (Shim ObjC++ TagLib: include/WineupID3.h, WineupID3.mm)
Tests/WineupLibraryTests/ (Fixtures.swift, ... )
```

### Padrão 1: Migrations e FTS5 com GRDB
```swift
// Fonte: experimento local (GRDB 7.11.1) e docs GRDB
var migrator = DatabaseMigrator()
migrator.registerMigration("v1") { db in
  try db.create(table: "audio_file") { t in
    t.autoIncrementedPrimaryKey("id")
    t.column("root_id", .integer).notNull().references("library_root")
    t.column("path", .text).notNull().unique()
    t.column("volume_uuid", .text); t.column("inode", .integer)
    t.column("size", .integer).notNull(); t.column("mtime_ns", .integer).notNull()
    t.column("status", .text).notNull().defaults(to: "present")
    t.column("content_hash", .blob)
  }
  try db.create(index: "audio_file_inode", on: "audio_file", columns: ["volume_uuid", "inode"])
  try db.execute(sql: """
    CREATE VIRTUAL TABLE track_fts USING fts5(title, artist, album,
      content='', tokenize='unicode61 remove_diacritics 2', prefix='2 3')
    """)
}
```
Tabela FTS: usar rowid = id da faixa/gravação; atualizar nas mesmas transações do scanner (ou `content=` com triggers). No benchmark: tabela de conteúdo externo + `INSERT INTO fts SELECT` em lote = 0,21 s para 100k. Para busca: sanitizar a entrada do usuário (escapar aspas, montar `"termo"*` por token) — não passar texto cru ao `MATCH`.

Pool: `var cfg = Configuration(); cfg.prepareDatabase { try $0.execute(sql: "PRAGMA synchronous=NORMAL") }`, `DatabasePool(path:configuration:)`; escritas serializadas em lotes de ~1000 linhas; leituras (UI) concorrentes. `PRAGMA foreign_keys=ON` (GRDB liga por padrão).

### Padrão 2: Identidade de arquivo
Armazene `volume_uuid` (`URLResourceKey.volumeUUIDStringKey`) + `st_ino` (do `stat`/`fts_statp`), mais `size` e `mtime` em nanossegundos (`st_mtimespec`). Para renomeação/movimentação na mesma volume o inode permanece (verificado em APFS e HFS+). Ver Q5 abaixo.

### Antipadrões
- **DELETE de arquivos ausentes:** viola LIB-03; só `status='missing'` (e `missing_since`). Ausência por volume desmontado: ao ver a raiz inacessível, NÃO marcar tudo como ausente de uma vez — marcar a raiz como "offline" e pular a varredura de remoção.
- **`replaceItemAt` sem atualizar `audio_file`:** o inode muda (verificado), a próxima varredura veria o arquivo como "novo" e "ausente" e duplicaria/perderia vínculos. A atualização do registro faz parte do TagWriter.
- **Ler `AudioFile(readingPropertiesAndMetadataFrom:)` p/ 100k arquivos mantendo capas em memória:** o SFB carrega as imagens (`attachedPictures`); extrair só o necessário, descartar as imagens e persistir capa à parte.
- **Cache de `URLResourceValues`:** a mesma instância de `URL` devolve valores em cache; após `replaceItemAt`/rename o `fileResourceIdentifier` voltou o valor antigo na mesma instância [VERIFIED: experimento]. Use `stat` ou chame `removeAllCachedResourceValues()` / crie nova URL.

## Não reinventar

| Problema | Não construir | Usar | Por quê |
|----------|---------------|------|---------|
| Busca sem acento | normalização manual de strings | FTS5 `unicode61 remove_diacritics 2` | Verificado, rápido |
| Migrations | scripts ad-hoc | `DatabaseMigrator` | ordem e idempotência |
| Escrita de tags | parser binário próprio | SFB / TagLib | formatos complexos |
| Troca atômica de arquivo | rename/delete manual | `FileManager.replaceItemAt` | preserva xattrs (verificado) e é atômico no mesmo volume |
| Cópia barata | `copyItem` sempre | `clonefile` com fallback | instantâneo e sem espaço em APFS |
| Geração de MP3/Opus/Vorbis p/ teste | binários commitados | `AudioConverter.convert` do SFB | sem encoders externos |
| Hash de conteúdo | hash do arquivo todo | hash parcial opcional (primeiros/últimos 64 KB + size), só sob demanda p/ desambiguar movidos | `content_hash` é opcional na decisão; ler 100k arquivos completos é inviável |

## Matriz de escrita de tags (Q2) — código lido e comportamento medido

Fonte: `.build/checkouts/SFBAudioEngine/Sources/CSFBAudioEngine/Metadata/*.mm` [VERIFIED: leitura de código] + experimento [VERIFIED].

| Formato | Writer (SFB → TagLib) | Campos desconhecidos | Padding / versão | Capas | Veredito |
|---------|----------------------|----------------------|------------------|-------|----------|
| FLAC | `SFBFLACFile.mm`: `TagLib::FLAC::File`; sempre grava Xiph comment; ID3v1/v2 só se já existirem; `removePictures()` e reinsere de `metadata.attachedPictures` | Preservados: setter só toca chaves conhecidas (`SetXiphComment` por chave). Medido: `MY_CUSTOM_FIELD` e `WAVEFORMATEXTENSIBLE_CHANNEL_MASK` sobreviveram a 2 gravações | bloco PADDING 4095↔4096 bytes (TagLib rebalanceia, ok) | Tipos 3 e 4 preservados (blocos PICTURE) | OK |
| MP3 | `SFBMP3File.mm`: `TagLib::MPEG::File`; `ID3v2Tag(true)` sempre; `file.save()` com defaults | Frames desconhecidos (TXXX, PRIV, WXXX) preservados | **Versão: v2.3 vira v2.4** (default do save). **Data apagada**: `removeFrames("TDRC")` e só regrava se `NSISO8601DateFormatter` parsear; "2019"/"2020-05-01" não parseiam, TYER também some. **Cria ID3v1** (rodapé `TAG` de 128 B) se ausente | APIC preservados com tipo (3 e 4) | **REPROVA SAFE-03** via SFB |
| M4A (AAC/ALAC) | `SFBMP4File.mm`: `TagLib::MP4::File` + `setMP4TagFromMetadata` | Átomos `----` (freeform) preservados (medido com `com.test:CUSTOM`) | n/a | `covr` regravado; **MP4 não guarda tipo**: front/back voltam como tipo 0 (Other) | OK, exceto tipo de capa (limitação do formato; documentar no teste) |
| Ogg Opus | `SFBOggOpusFile.mm`: `TagLib::Ogg::Opus::File` + Xiph | Preservados (`MY_CUSTOM_FIELD`, `ENCODER`) | n/a | `METADATA_BLOCK_PICTURE` com tipos 3/4 preservados | OK |
| Ogg Vorbis (extra) | idem Xiph | Preservados | n/a | tipos preservados | OK |
| WAV | `SFBWAVEFile.mm`: `TagLib::RIFF::WAV::File`; INFO só se existir; ID3v2 sempre (chunk `ID3 ` após `data`) | — | mesma regra de data do MP3: **data apagada** | tipos 3/4 preservados | **REPROVA data**; versão v2.4 default |

Pontos adicionais do código: o setter ID3 remove (e só regrava se o campo do `SFBAudioMetadata` estiver preenchido) TCOM, TPE2, TBPM, POPM, TRCK, TCMP, TPOS, USLT, TSRC, TSO*, TIT1, RVA2, TXXX de ReplayGain e MusicBrainz. Isso é seguro apenas na medida em que o leitor popula esses campos de forma simétrica; a data é a assimetria encontrada. Por isso o verificador compara TODOS os campos lidos antes/depois, não só os alterados.

### ID3 direto via TagLib (provado)
`TagLib::MPEG::File(&stream,false)`; `ID3v2Tag(true)->setTitle(...)`; `save(MPEG::File::ID3v2, File::StripNone, ID3v2::v3|v4, File::DoNotDuplicate)`. Resultado medido: v2.3 permaneceu 2.3 (frames PRIV e TYER intactos), v2.4 permaneceu 2.4 (TDRC e PRIV intactos), sem rodapé ID3v1, data lida corretamente após gravar. Para WAV usar `TagLib::RIFF::WAV::File` com `ID3v2Tag()` e o mesmo critério. A versão original é lida do cabeçalho do arquivo (byte 3 do tag) antes de gravar. Estratégia: o backend de ID3 edita apenas campos presentes no `changes` (title/artist/album/trackNumber/year etc.), usa `setTitle` e afins e, para ano, escreve TDRC (v4) ou TYER (v3) sem reformatar.

O código-fonte de teste do shim (apagado com o diretório de experimento) está em `/private/tmp/claude-501/-Users-macmini-Documents-witchmymac/5d6cf8a4-8169-479d-a6e8-456719335e81/scratchpad/keep/Shim.mm` (30 linhas) como ponto de partida.

## Fixtures (Q3) — todas geráveis localmente

| Formato | Como | Tamanho (1 s estéreo) |
|---------|------|-----------------------|
| WAV | `python3 -I` com módulo `wave` (seno), em `mktemp -d` | 176 KB |
| FLAC | `afconvert -f flac -d flac a.wav a.flac` | 27 KB |
| M4A (AAC) | `afconvert -f m4af -d aac a.wav a.m4a` | 11 KB |
| ALAC | `afconvert -f m4af -d alac a.wav al.m4a` | 40 KB |
| MP3 | `AudioConverter.convert(wavURL, to: mp3URL)` (SFB/LAME) | 16 KB |
| Ogg Opus | `AudioConverter.convert(wavURL, to: opusURL)` (SFB/libopus 1.6.1) | 17 KB |
| Ogg Vorbis | idem com `.ogg` | 9 KB |

`afconvert` NÃO escreve MP3 nem Ogg (`ExtAudioFileWrite failed 'fmt?'`) [VERIFIED]. Não existe `ffmpeg/lame/opusenc/oggenc/flac/sox` instalados. Fixtures com campos desconhecidos: FLAC/Opus via `metadata.additionalMetadata = ["MY_CUSTOM_FIELD": "keepme"]`; MP3 injetando frames ID3 crus em Swift (`Data`) antes dos quadros MPEG (v2.3 e v2.4, TXXX/PRIV/WXXX/TDRC/TYER); M4A inserindo um átomo `----` no `ilst` (soma o tamanho nos pais moov/udta/meta/ilst; as posições `stco` ficam inconsistentes, mas o teste só relê tags); WAV: sem tag inicial (o SFB cria o chunk `ID3 `). Não há como o SFB gerar tag desconhecida por conta própria em MP3/M4A, então a injeção crua é necessária. O fixture deve ser criado na hora dentro de `NSTemporaryDirectory()` com `defer` de remoção (Swift Testing: usar um helper `withTempDir`). Duração via `file.properties.duration`: para AAC o valor medido variou (1,068 s vs 1,0 s), então compare duração com tolerância (ex.: 50 ms) ou compare antes/depois do mesmo formato, não contra o WAV de origem.

## Sistema de arquivos (Q4, Q5)

Medido em APFS (volume de dados) e numa imagem HFS+ de 8 MB (descartada) [VERIFIED].

| Operação | APFS | HFS+ / outro volume |
|----------|------|---------------------|
| `clonefile(src,dst,0)` | ok, novo inode, mesmos blocos (`st_blocks` iguais, sem espaço extra), xattrs copiados | HFS+: `errno 45 ENOTSUP`; entre volumes: `errno 18 EXDEV` |
| `FileManager.copyItem` | ok, xattrs copiados | ok (cópia real; funciona entre volumes) |
| `replaceItemAt(orig, withItemAt: work)` | **inode muda** (30948997→30949001); xattrs do original **preservados** mesmo que a cópia de trabalho não os tivesse; retorna `URL?` | igual |
| `Data.write(options: .atomic)` | inode muda | inode muda |
| gravação in-place (`FileHandle`) | inode mantido | idem |
| `moveItem` (rename) no mesmo volume | inode mantido | idem |

Consequências para o plano:
- Backup: tentar `clonefile`; em `ENOTSUP`/`EXDEV` cair para `copyItem` em `~/Library/Application Support/Wineup/Backups/<uuid>/`. O fallback consome espaço real: **checar espaço livre (`volumeAvailableCapacityForImportantUsageKey`) antes e abortar sem tocar no arquivo se faltar** (o disco do usuário está ~98%). Backups clonados só ocupam o delta de blocos reescritos.
- O mesmo `clonefile` é bom para a cópia de trabalho (no mesmo diretório do original, para o `replaceItemAt` ser atômico no mesmo volume).
- Após `replaceItemAt`, o TagWriter deve fazer `stat` e atualizar `inode/size/mtime` em `audio_file` na mesma transação do journal. No `undo`, repetir.
- Se a pasta do arquivo não for gravável, `replaceItemAt` falha: tratar como erro do TagWriter sem efeitos colaterais (o backup já criado deve ser removido ou marcado órfão).

### Identidade rápida (Q5)
- `URLResourceKey.fileResourceIdentifierKey` devolve `NSData` opaco de 16 bytes; em APFS os 8 primeiros bytes são o `st_ino` (little-endian) [VERIFIED: 0x853ed801 = 30948997]. Compara-se com `isEqual`, mas a documentação trata como opaco e não persistível. Também fica em cache por instância de URL (pitfall acima).
- `st_ino` via `stat`/`fts(3)` é mais barato (já vem no `stat` que o scanner faz) e persistível. **Recomendação:** persistir `(volume_uuid, st_ino)`; `volume_uuid` via `volumeUUIDStringKey` da raiz (uma chamada por raiz, não por arquivo). Não usar `st_dev` sozinho (muda entre montagens) [ASSUMED]. Inodes em APFS não são reutilizados com frequência, mas podem colidir após apagar/recriar: combinar sempre com `size` (e `mtime` quando não houve gravação do Wineup) para aceitar "mesmo arquivo movido".
- Detecção de movido: ao fim da etapa 1, linhas `present` não vistas + arquivos vistos sem registro; casar por `(volume_uuid, inode, size)`; se houver ambiguidade, casar por `(size, mtime)` e, opcionalmente, hash parcial. Se nada casar -> `missing`.
- Cópias entre volumes/restauração de backup: sem inode estável; o fallback é `size+mtime(+hash parcial)`, e só o usuário "re-localizando" a raiz resolve o resto.

## Desempenho de varredura (Q6)

Medições em debug (a parte pesada é C), cache quente, arquivos vazios criados em `mktemp -d` (500 pastas x 200 arquivos; ~23 MB de metadados; removidos) [VERIFIED]:

| Estratégia (100 mil arquivos) | Tempo |
|-------------------------------|-------|
| `FileManager.enumerator` + resourceValues (size, mtime, isRegularFile) | 0,36 s |
| idem + `fileResourceIdentifierKey` | 0,36 s |
| `readdir` + `lstat` recursivo | 0,22 s |
| `fts(3)` com `stat` (ino, size, mtimespec) | **0,10 s** |

SQLite (100 linhas lotes de 1000; `synchronous=NORMAL`; WAL): 100k INSERTs em 1,11 s; FTS5 em lote 0,21 s; carga do mapa path->(size,mtime,inode) 0,07 s; arquivo `.sqlite` de 26 MB; busca (`ORDER BY rank LIMIT 200`) 1,5–30 ms, contagem total <2 ms. Leitura SFB de tags: ~0,15 ms/arquivo pequeno (FLAC/MP3/M4A de 1 s, cache quente) — arquivos reais com capas de MB e disco frio serão bem mais lentos; por isso a etapa 2 deve ser limitada a arquivos alterados e rodar em paralelo moderado (p.ex. `withTaskGroup` com 4–6 tarefas) com a escrita no banco em um único writer.

Estratégia recomendada: etapa 1 com `fts(3)` (ou `FileManager.enumerator` se o planejador preferir API Foundation: 0,36 s já é irrelevante) executada fora da main; comparação em memória contra o mapa carregado; lotes de ~500–1000 por `pool.write`; `Task.checkCancellation()` por lote e emissão de `ScanProgress` (enumerados, lidos, total estimado). Testes de escala: 100k em memória/SQLite direto (sem arquivos); um teste de enumeração com 5–10k arquivos vazios em tmp (rápido, sem pressão de disco); o teste de 100k arquivos vazios só como script opcional (custou ~23 MB e 3 s para criar/apagar) ou em teste marcado como pesado.

## Armadilhas comuns

### 1. SFB apaga a data em MP3/WAV
**O que acontece:** `releaseDate` só é escrita se `NSISO8601DateFormatter` (opções padrão = timestamp completo com fuso) parsear; senão TDRC é removido e nada o substitui. **Como evitar:** backend ID3 próprio (TagLib) e/ou verificador antes/depois que falha o `TagWriter` quando um campo não alterado muda. **Alerta:** teste com fixture com `TDRC=2019` e `TYER=2018`.

### 2. Versão ID3 2.3 -> 2.4 e rodapé ID3v1 criado
**Como evitar:** `save(..., version, DoNotDuplicate)` com a versão lida do arquivo; o backend nunca chama `file.save()` com defaults. **Alerta:** o verificador compara versão de cabeçalho e presença de `TAG` nos últimos 128 bytes (antes/depois).

### 3. Perder vínculo após `replaceItemAt` (inode novo)
Ver acima: atualizar `audio_file` no mesmo passo. Teste: gravar tag, rodar scanner, afirmar que não houve duplicata nem `missing`.

### 4. Marcar tudo como ausente quando um volume é desmontado
Antes de marcar `missing`, verificar que a raiz existe e é legível; caso contrário `library_root.online=false` e nenhuma mudança de status (LIB-03).

### 5. Tipo de capa em M4A
MP4 `covr` não tem tipo: front/back voltam como `Other (0)`. O teste SAFE-03 para M4A deve afirmar o número de imagens e bytes, não o tipo.

### 6. Espaço em disco
Backup por cópia + arquivo de trabalho podem faltar espaço (~98% cheio). Checar capacidade antes; falhar cedo; limpeza de backups órfãos; política de retenção simples (ex.: manter N entradas ou X GB — [ASSUMED], decidir com o usuário).

### 7. Concorrência e Swift 6/strict
`-strict-concurrency=complete` é usado no core; GRDB 7 é compatível (compilou no Swift 5 mode do pacote). `DatabasePool` é `Sendable`; evitar compartilhar `AudioFile` (não Sendable) entre tarefas. O banco do usuário não deve ser aberto pelos testes: usar caminho temporário (ou `DatabaseQueue()` em memória só para FTS; WAL exige arquivo).

### 8. Consultas FTS com entrada crua
Termos com `"`, `*`, `-`, `AND` quebram o `MATCH`. Tokenizar, remover operadores e montar `"tok1"* "tok2"*`.

### 9. Leitor do app (TrackLoader) acopla NSImage
Não reutilizar `TrackLoader` no WineupLibrary (target app, AppKit). Criar `TagReader` que devolve valor `Sendable` (struct) e, em separado, as capas (dados) quando pedidas.

## Exemplos de código

### Leitura e escrita via SFB (FLAC/M4A/Opus)
```swift
// Fonte: .build/checkouts/SFBAudioEngine (SFBAudioFile.h) + experimento
let file = try AudioFile(readingPropertiesAndMetadataFrom: url)   // lê tudo
file.metadata.title = "Novo"
try file.writeMetadata()            // mesmo objeto; opera no arquivo em disco
```
Sempre aplicar à **cópia de trabalho**, nunca ao original.

### Fixtures MP3/Opus/Vorbis
```swift
try AudioConverter.convert(wavURL, to: tmpDir.appendingPathComponent("a.mp3"))   // .opus, .ogg idem
```

### Backup com clonefile + fallback
```swift
func backup(_ src: URL, to dst: URL, fallback: URL) throws -> URL {
    if clonefile(src.path, dst.path, 0) == 0 { return dst }
    guard errno == ENOTSUP || errno == EXDEV else { throw POSIXError(POSIXErrorCode(rawValue: errno)!) }
    try FileManager.default.copyItem(at: src, to: fallback)
    return fallback
}
```

### Troca atômica
```swift
let result = try FileManager.default.replaceItemAt(original, withItemAt: workCopy)   // URL?
var st = stat(); stat(original.path, &st)    // novo st_ino/mtime/size -> atualizar audio_file
```

## Estado da arte

| Antigo | Atual | Impacto |
|--------|-------|---------|
| GRDB 6 (tools 5.7) | GRDB 7.x (tools 6.1, SQLite do sistema, `Sendable`) | Exige toolchain >= 6.1 (ok: Swift 6.4 nas CLT) |
| `copyItem` simples | `clonefile` | backup grátis em APFS |

## Log de suposições

| # | Afirmação | Seção | Risco se errada |
|---|-----------|-------|-----------------|
| A1 | O usuário aceita um alvo ObjC++ TagLib para MP3/WAV (desvio da decisão "via SFB writeMetadata") | Resumo/Stack | Sem isso SAFE-03 não pode ser cumprido para MP3 (versão/data/ID3v1); alternativa: aceitar e documentar a limitação, o que reprova o critério de sucesso 5 |
| A2 | `st_dev` instável entre montagens | Identidade | baixo; usar volume UUID de qualquer forma |
| A3 | Retenção de backups (N entradas/X GB) | Pitfall 6 | definir política com o usuário |
| A4 | Hash parcial só como desempate de movidos | Não reinventar | baixo |
| A5 | Tempos de varredura em disco frio/externo serão maiores que os medidos (cache quente) | Desempenho | metas de UX; medir na Fase de integração |
| A6 | Comportamento de `replaceItemAt` em volumes de rede/exFAT não testado (só APFS e HFS+) | Sistema de arquivos | fallback de cópia pode ser necessário |

## Perguntas em aberto

1. **Aprovar o backend TagLib para MP3/WAV?** O que se sabe: SFB reprova versão/data/ID3v1; shim provado. Recomendação: sim (alvo `WineupID3`), SFB para os demais; o verificador antes/depois fica como rede de segurança em qualquer caso.
2. **WAV com chunk LIST INFO existente:** não testado (o fixture WAV gerado só tem fmt+data). Recomendação: incluir no teste um WAV com `LIST/INFO` montado em Swift/`Data`.
3. **Capas grandes em 100k arquivos:** não medido; avaliar se vale ler propriedades sem metadados completos (o init `readingPropertiesAndMetadataFrom` lê tudo).
4. **Política de retenção/limpeza do diretório de backups.**

## Disponibilidade de ambiente

| Dependência | Necessária para | Disponível | Versão | Alternativa |
|-------------|-----------------|-----------|--------|-------------|
| Swift toolchain (CLT) | build/test | sim | Swift 6.4 (swiftlang-6.4.0.34.1) | — |
| GRDB.swift via rede | resolução SwiftPM | sim | 7.11.1 | — |
| SQLite do sistema com FTS5 | busca | sim | 3.54.0 | — |
| `afconvert` | fixtures WAV/FLAC/M4A/ALAC | sim | /usr/bin | — |
| ffmpeg, lame, opusenc, oggenc, flac, sox | fixtures | não | — | SFB `AudioConverter` (LAME/libopus/libvorbis embutidos) |
| Espaço em disco | builds | ~4,9 GB livres (98%) | — | experimentos usam KB; evitar builds duplicados (uma cópia `.build` de 1,9 GB; foi clonada por APFS e apagada) |
| `hdiutil` (volume HFS+ p/ teste não-APFS) | teste opcional | sim | — | testes unitários do fallback injetando erro |

## Arquitetura de validação

### Framework de teste
| Propriedade | Valor |
|-------------|-------|
| Framework | Swift Testing (CLT), já em uso em `WineupCoreTests` |
| Config | `Package.swift` (novo `WineupLibraryTests`), `scripts/test.sh` (passa `-plugin-path`) |
| Comando rápido | `./scripts/test.sh --filter WineupLibraryTests` |
| Suíte completa | `./scripts/test.sh` + `swift build -c release`; fim da fase: `./scripts/build-app.sh` |

### Requisitos -> testes
| Req | Comportamento | Tipo | Comando | Arquivo existe? |
|-----|---------------|------|---------|-----------------|
| LIB-01 | Adicionar raiz, fechar e reabrir `DatabasePool` no mesmo arquivo e ler as raízes/faixas | integração (db temporário) | `./scripts/test.sh --filter LibraryPersistenceTests` | Wave 0 |
| LIB-02 | 2ª varredura sem mudanças lê 0 arquivos; alterar 1 arquivo lê 1; progresso emitido; cancelar interrompe e deixa DB consistente | integração (fixtures minúsculas) | `--filter ScannerTests` | Wave 0 |
| LIB-03 | rename => mesmo registro (path novo, mesmo id); apagar => `missing`; raiz inacessível => nada marcado; playlist/histórico (linhas de referência) intactos | integração | `--filter MissingFilesTests` | Wave 0 |
| LIB-04 | "beyonce" acha "Beyoncé"; prefixo; entrada com aspas/operadores não quebra; 100k linhas sintéticas: resposta < 100 ms (limiar folgado) | integração (inserção direta no DB) | `--filter SearchTests` | Wave 0 |
| LIB-05 | consultas artista/álbum/gênero/pasta/todas retornam contagens esperadas | integração | `--filter BrowseTests` | Wave 0 |
| LIB-06 | migration v1 cria as tabelas; relação arquivo/gravação/faixa-no-lançamento/lançamento; `release.kind` origem; `unknown` nunca vira single | unitário/integração | `--filter SchemaTests` | Wave 0 |
| LIB-07 | 100k linhas: inserção em lotes + busca sem travar a main (teste mede tempo e roda o scanner fora da main); enumeração de 5–10k arquivos vazios | desempenho (pesado, marcado) | `--filter ScaleTests` | Wave 0 |
| SAFE-01 | Fluxo completo: backup criado, verificação executada, journal registrado; falha na verificação mantém o original intacto; `dryRun` não toca o arquivo (hash igual) | integração (fixtures) | `--filter TagWriterTests` | Wave 0 |
| SAFE-02 | `undo` restaura bytes iguais ao original (hash); atualiza `audio_file`; recusa se o arquivo mudou depois | integração | `--filter TagWriterUndoTests` | Wave 0 |
| SAFE-03 | Para FLAC, MP3(v2.3 e v2.4), M4A, Opus, WAV (e Vorbis): gravar e reler preserva campos desconhecidos, data, versão ID3, ausência de ID3v1 novo, nº/bytes/tipo de capas (M4A: só nº/bytes) | integração (fixtures geradas) | `--filter TagPreservationTests` | Wave 0 |

### Taxa de amostragem
- Por commit de tarefa: `./scripts/test.sh --filter <suite relevante>`
- Por onda: `./scripts/test.sh` + `swift build -c release`
- Gate da fase: `./scripts/build-app.sh` verde antes de `/gsd-verify-work`

### Lacunas da Wave 0
- [ ] `Tests/WineupLibraryTests/Support/Fixtures.swift` — gerador de WAV/FLAC/M4A/ALAC (afconvert via `Process`), MP3/Opus/Vorbis (SFB), injeção crua de ID3/átomos, `withTempDir`
- [ ] `Tests/WineupLibraryTests/Support/TagProbe.swift` — leitores crus (versão ID3, frames, presença ID3v1, chaves Xiph, átomos `ilst`)
- [ ] `Package.swift`: targets `WineupLibrary`, `WineupID3` (se aprovado), `WineupLibraryTests`, dependência GRDB
- [ ] Executar a tarefa de Package primeiro e rodar `swift package resolve` (rede) — GRDB é novo; o primeiro build baixa e compila (cerca de 1–2 min)

## Domínio de segurança

`security_enforcement` não está desativado em `.planning/config.json`; app local sem sandbox, sem rede nesta fase.

| Categoria ASVS | Aplica | Controle |
|----------------|--------|----------|
| V2/V3 Autenticação/Sessão | não | — |
| V4 Controle de acesso | parcial | acesso a pastas só via `LibraryRoot`; gravação apenas dentro de raízes registradas (`contains`) |
| V5 Validação de entrada | sim | FTS: sanitizar; caminhos: padronizar e checar prefixo; parâmetros SQL sempre via argumentos GRDB |
| V6 Criptografia | não | hash opcional é só identidade (SHA-256 do CryptoKit se usado), nunca segredo |

| Padrão de ameaça | STRIDE | Mitigação |
|------------------|--------|-----------|
| Injeção SQL | Tampering | argumentos vinculados GRDB; nunca interpolar |
| Path traversal / symlink fora da raiz | Tampering | `standardizedFileURL` + `resolvingSymlinksInPath` antes de `contains`; `fts` com `FTS_PHYSICAL` não segue links |
| Arquivo de áudio malformado derrubando o parser | DoS | leitura em `try`, arquivo problemático marcado com erro e pulado, nunca derruba a varredura |
| Corrupção por escrita interrompida | Tampering | cópia de trabalho + `replaceItemAt` atômico + backup; sinal de cancelamento não interrompe entre `replaceItemAt` e o commit do journal |
| Vazamento de caminhos em logs | Information Disclosure | mensagens de erro sem dados sensíveis (regra do projeto) |

## Fontes

### Primárias (ALTA)
- Experimentos locais (cópia APFS do projeto, apagada): GRDB 7.11.1 + FTS5, SFB write por formato, clonefile/replaceItemAt/HFS+, benchmarks.
- Código-fonte do SFBAudioEngine 0.14.0 em `.build/checkouts/SFBAudioEngine/Sources/CSFBAudioEngine/Metadata/` (`SFBMP3File.mm`, `SFBFLACFile.mm`, `SFBMP4File.mm`, `SFBOggOpusFile.mm`, `SFBWAVEFile.mm`, `SFBAudioMetadata+TagLibID3v2Tag.mm`, `...XiphComment.mm`, `...MP4Tag.mm`) e headers `SFBAudioFile.h`, `SFBAudioMetadata.h`, `SFBAttachedPicture.h`, `SFBAudioConverter.h`.
- `https://raw.githubusercontent.com/groue/GRDB.swift/v7.11.1/Package.swift` (tools 6.1, define `SQLITE_ENABLE_FTS5`); API de releases do GitHub (v7.11.1).

### Secundárias / Terciárias
- Nenhuma fonte web adicional; o comportamento de `fileResourceIdentifierKey` ser opaco vem do conhecimento da documentação da Apple [ASSUMED], o resto foi medido.

## Metadados
**Confiança:** pilha ALTA (compila/roda); arquitetura MÉDIA (sugestões); armadilhas ALTA (reproduzidas).
**Data da pesquisa:** 2026-10-20. **Válido até:** ~30 dias (SFB/GRDB mudam por release).

## RESEARCH COMPLETE
