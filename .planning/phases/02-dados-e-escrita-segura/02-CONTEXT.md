# Phase 2: Dados e Escrita Segura - Context

**Gathered:** 2026-10-20
**Status:** Ready for planning
**Mode:** Auto-generated (discuss skipped via workflow.skip_discuss; decisões da pesquisa do projeto e da Fase 1)

<domain>
## Phase Boundary

A biblioteca do usuário persiste entre sessões, é varrida e pesquisada com rapidez, e qualquer gravação de tag é protegida por backup, verificação e desfazer. Requisitos: LIB-01..07, SAFE-01..03, NAV-01. A UI de edição de tags (SAFE-04) e o Fixer ficam para a Fase 7; aqui a escrita segura existe e é testada, sem UI de edição.

</domain>

<decisions>
## Implementation Decisions

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

- **Decisão A1 (aceita em modo autônomo, 2026-10-20):** `TagWriter` com backend plugável por formato. FLAC, M4A/ALAC, Ogg Opus/Vorbis gravam via SFBAudioEngine `writeMetadata`; **MP3 e WAV gravam via um target ObjC++ fino sobre TagLib** (produto `taglib` do `CXXTagLib`, já dependência da SFB), porque o `writeMetadata` da SFB converte ID3v2.3→2.4, apaga datas parciais ("2019") e cria ID3v1 — viola SAFE-03. TagLib é LGPL-2.1/MPL-1.1 (MPL permite linkagem estática); registrar em THIRD_PARTY_NOTICES. O verificador pós-gravação compara **todos** os campos lidos antes/depois, não só os alterados.
- `TagWriter` atualiza `audio_file` (inode, mtime, tamanho) na mesma transação do journal, pois `replaceItemAt` troca o inode.
- Identidade de arquivo persistida como `(volume_uuid, st_ino)` + tamanho + mtime via `stat`/`fts` (não `fileResourceIdentifierKey`, que fica em cache por URL).
- Verificar espaço livre antes de backup; volume desmontado não marca a raiz inteira como `missing`.

- **NAV-01 (pedido do usuário):** na primeira abertura (banco sem raízes), adicionar `~/Music` (`FileManager.default.urls(for: .musicDirectory, in: .userDomainMask)`) como raiz e iniciar a varredura automaticamente; se a pasta não existir ou estiver vazia, o app abre normalmente sem erro.
- O modelo de dados deve suportar as visões futuras (Fase 4/5): gênero nulo vira "Sem categoria"; álbum nulo ou com uma faixa entra no álbum virtual "Singles" (consulta, nunca tag); marcações de cor por faixa e playlists precisam de tabelas próprias que serão exportadas no perfil do usuário (PROF-01/02).

### Claude's Discretion
Demais escolhas a critério do pesquisador/planejador, guiadas pelos critérios de sucesso do ROADMAP.

</decisions>

<code_context>
## Existing Code Insights

- Targets: `WineupCore` (Foundation puro: Track/TrackID/TrackList/Clock, portas `AudioEngine`, `LibraryStore`, `TagIO`, `MetadataProvider`, `LibraryRoot`, `Confidence`, `TagDiff`, journal), `Wineup` (app SwiftUI + `TrackLoader` com SFBAudioEngine), `WineupCoreTests` (Swift Testing).
- `scripts/test.sh` é a entrada única de testes (passa `-plugin-path` do TestingMacros das CLT).
- `.build/checkouts/SFBAudioEngine` tem `SFBAudioFile.h` com `writeMetadata`.

</code_context>

<specifics>
## Specific Ideas

Ver `.planning/research/{STACK,ARCHITECTURE,PITFALLS}.md` (armadilhas 1, 2, 6, 7, 8, 17) e os itens [VERIFICAR] 2, 8, 9, 10, 11 do SUMMARY.

</specifics>

<deferred>
## Deferred Ideas

UI de edição de tags (Fase 7), navegação de discografia na UI (Fase 5), fila/playlists (Fase 4).

</deferred>
