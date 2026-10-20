# Phase 4: Serviços de Reprodução - Context

**Gathered:** 2026-10-20
**Status:** Ready for planning
**Mode:** Auto-generated (discuss skipped via workflow.skip_discuss)

<domain>
## Phase Boundary

A reprodução passa a funcionar sobre a biblioteca persistente, com fila, playlists e sessão restaurável, mais o perfil do usuário exportável. Requisitos: PLAY-01..04, DISC-02, NAV-03, PROF-01, PROF-02. Serviços sem UI nova pesada (redesign/navegação completa é Fase 5); ligar o mínimo ao app para provar ponta a ponta.

</domain>

<decisions>
## Implementation Decisions

- Novo target `WineupServices` (depende de WineupCore, WineupLibrary, WineupAudio) com `PlaybackController` (fila, repetir uma/todas, embaralhar, avanço via `NextTrackPlanner`/gapless do adaptador), `PlaylistService` (CRUD nas tabelas `playlist`/`playlist_item` da Fase 2, import/export M3U/M3U8 com caminhos relativos e absolutos, UTF-8), `SessionStore` (fila, faixa e posição em `app_setting`, restaurados ao abrir), `ArtworkResolver` (arte embutida → imagem na pasta `cover/folder/front.jpg|png` → capa do lançamento → placeholder; nunca grava; cache em memória).
- **NAV-03 (pedido do usuário):** o álbum virtual "Singles" — faixas sem álbum e de álbuns com uma única faixa — já existe como consulta na Fase 2 (`BrowseService`); garantir que a fila/"Reproduzir tudo" e a navegação de álbum o tratem como álbum normal.
- **PLAY-04:** "Reproduzir tudo" de um artista deduplica a mesma gravação (mesmo `recording` ou mesmo título normalizado + duração ±2 s + artista) presente em single e álbum; configurável (padrão: evitar repetição); nunca remove arquivos.
- **Playlists de cor (preparar para NAV-04 da Fase 5):** consulta que gera uma playlist automática por `MarkColor` existente em `track_mark` (só cores com ≥1 faixa); `PlaylistService` expõe isso; flag `playlists.showColorTags` em `app_setting`.
- **PROF-01/02 (pedido do usuário):** `ProfileService` exporta para um arquivo `.wineupprofile` (JSON versionado, UTF-8; opcionalmente zip) contendo: playlists (itens identificados por caminho + título/artista/duração para reencontrar em outra máquina), marcações de cor por faixa, preferências (layout, tema, visão, flags), presets e estado de EQ, sessão. Importar com prévia (contagens, conflitos) e mescla (não apaga dados existentes; playlists com nome igual ganham sufixo); faixas não encontradas são reportadas. Salvamento automático do perfil local acontece pelo próprio banco; exportar/importar via menu Arquivo.
- Marcações de cor (as bolinhas da UI) passam a ser persistidas em `track_mark` em vez de só em memória.
- Gate por plano: `swift build -c release && ./scripts/test.sh`; fim da fase: `./scripts/audiocheck.sh && ./scripts/build-app.sh`. Testes nunca usam a biblioteca real (WINEUP_LIBRARY_PATH temporário); arquivos de perfil de teste em `mktemp -d`.

### Claude's Discretion
Demais escolhas a critério do planejador. Fase sem pesquisa (padrões estabelecidos), mas o planejador deve ler o código das Fases 2–3.

</decisions>

<code_context>
## Existing Code Insights

- WineupLibrary: esquema v1 com `playlist`, `playlist_item`, `track_mark`, `app_setting`, `release`/`release_track`; `BrowseService` (inclui Singles virtual e "Sem categoria"), `SearchService`, `Scanner`, `LibraryController` no app, `EqPresetStore`.
- WineupAudio: `SFBAudioEngineAdapter` com `enqueueNext`/`onNowPlayingChanged`; WineupCore: `NextTrackPlanner`, `RateMapping`.
- App: `PlayerState` concentra estado; ColorDots/MarkColor na UI.

</code_context>

<specifics>
## Specific Ideas

Ver `.planning/research/FEATURES.md` (fila, playlists, M3U) e PITFALLS (armadilhas 13, 18, 19).

</specifics>

<deferred>
## Deferred Ideas

Seletor de visões e página de artista na UI (Fase 5); teclas de mídia (Fase 6).

</deferred>
