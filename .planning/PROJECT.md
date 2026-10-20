# Wineup Player

## What This Is

Player de música nativo para macOS (Swift + SwiftUI), inspirado na identidade e na experiência do Winamp clássico (1999–2005): painéis independentes (player, equalizador, playlist, busca, letras, capa), skins/temas e controle total do usuário sobre a biblioteca. O diferencial planejado é o **Wineup Library Fixer**, um assistente integrado que corrige tags, capas, letras e duplicatas com prévia, nível de confiança e opção de desfazer. Para quem tem coleção local de músicas, gosta da estética retrô e quer organizar tudo sem alternar entre vários aplicativos.

## Core Value

Tocar a biblioteca local do usuário de forma confiável, com a interface clássica de painéis, e nunca danificar os arquivos dele.

## Requirements

### Validated

<!-- Já existe e foi verificado no app atual (build local, 2026-10-19). -->

- ✓ Interface de painéis (AMP, FX, Playlist, Search, Lyrics, Capa) em três disposições (Grade, Compacto, Estúdio) e três temas (Grafite, Vinho, Verde) — existing
- ✓ Abrir arquivos e pastas (⌘O, arrastar, Abrir com) e tocar FLAC/M4A/WAV com play, pause, stop, anterior, próxima, busca e volume — existing
- ✓ Leitura de tags, duração, capa e letra embutidas via SFBAudioEngine — existing
- ✓ Equalizador de 10 bandas + preamp aplicado ao áudio (cadeia monta sem erro) — existing
- ✓ `.app` gerado por `scripts/build-app.sh` com ícone, frameworks LGPL dinâmicos embutidos e avisos de terceiros — existing

### Active

- [ ] Espectro e medidor de nível (VU) ligados ao áudio real
- [ ] Velocidade de reprodução e balanço funcionando
- [ ] Biblioteca persistente (SQLite) com varredura incremental, busca e restauração de estado entre sessões
- [ ] Playlists salvas, fila de reprodução, repetir/embaralhar
- [ ] Controles de mídia do sistema, atalhos de teclado e Now Playing
- [ ] Modelo de dados separando arquivo, gravação, lançamento, artista, arte e letra
- [ ] Navegação por artista/álbum/single com capas e fallback visual (sem reescrever tags)
- [ ] Biblioteca carrega `~/Music` por padrão; visões por Álbum, Banda, Pastas, Estilo (com "Sem categoria") e Playlists
- [ ] Álbum virtual "Singles" para faixas sem álbum ou de álbuns com uma faixa
- [ ] Playlists automáticas por cor de tag (só quando há faixas marcadas, desativáveis)
- [ ] Perfil do usuário (playlists, tags, preferências, EQ) salvo, exportável e importável
- [ ] Seletor de design de exibição da janela/conteúdo
- [ ] Letras `.lrc` sincronizadas
- [ ] Wineup Library Fixer: diagnóstico, prévia com confiança, gravação controlada de tags e desfazer
- [ ] Reconhecimento por impressão acústica e provedores de metadados/capas (opcionais, com aviso de privacidade)
- [ ] Skins: formato próprio documentado; avaliar leitura de skins clássicas `.wsz`
- [ ] Equalizador com presets persistentes, ReplayGain não destrutivo
- [ ] Testes automatizados (unidade e integração) do núcleo; assinatura e notarização para distribuição

### Out of Scope

- Reutilizar código do repositório do Winamp (manfromafar/winamp) — a Winamp Collaborative License proíbe distribuir versões modificadas e sublicenciar; serve só para estudar comportamento
- Copiar código GPL/LGPL (Mixxx, Cog, projectM, plugins WACUP GPL) — estudar algoritmos e reescrever; bibliotecas LGPL só por linkagem dinâmica
- Reutilizar componentes sem licença (WACUP gen_waveseek, in_notyansf, in_vgm-libvgm, vgmplay) — sem licença, todos os direitos reservados
- Contornar licenças de apps de terceiros (ex.: AMP descontinuado) — o AMP serve apenas como referência de comportamento observável
- Suporte a plugins do Winamp e compatibilidade universal com skins — escopo explícito e documentado, sem promessa de compatibilidade total
- Versões Windows e Linux — o foco passou a ser macOS nativo; Windows fica para uma decisão futura
- Processamento destrutivo de áudio (normalização que regrava amostras) — só análise/ReplayGain não destrutivo, e qualquer processamento destrutivo exige consentimento explícito

## Context

- **Estado atual:** protótipo funcional em `/Users/macmini/Documents/VSCode Temp/Wineup Player` (Swift Package, ~25 arquivos). A interface seguiu prints do AMP (app Intel descontinuado) como referência visual; nenhum código do AMP foi usado.
- **Briefing de produto:** `Wineup_Player_contexto_projeto.md` (também resumido na memória do usuário, `wineup-player.md`). A decisão de UI em aberto no briefing (Slint vs Tauri) foi substituída por Swift/SwiftUI nativo.
- **Referências auditadas** em `/Users/macmini/Documents/VSCode Temp/Wineup References` (31 repositórios WACUP + Winamp, AudioKit, SFBAudioEngine, Cog, Audacious, Mixxx, projectM, TagLib). Decisões de licença em `wineup-references.md` (memória).
- **Ambiente:** só Command Line Tools (sem Xcode completo); build via SwiftPM e `scripts/build-app.sh`, assinatura ad-hoc.
- **Dívida conhecida:** VU/espectro simulados, velocidade/balanço só visuais, biblioteca em memória, sem testes automatizados, efeito audível do EQ não verificado.

## Constraints

- **Plataforma**: macOS 14+ (Swift 5.9 tools, SwiftUI) — SFBAudioEngine exige 11+, o app usa recursos do 14
- **Licenças**: dependências MIT/BSD/Apache preferidas; LGPL só como frameworks dinâmicos substituíveis, com avisos em `THIRD_PARTY_NOTICES.md`
- **Segurança dos arquivos**: nunca gravar tags, renomear ou mover sem prévia, confiança visível e backup — arquivos do usuário têm prioridade sobre automação
- **Privacidade**: sem telemetria; consultas externas (metadados, AcoustID) opcionais, informando o que é enviado, com modo offline
- **Ferramentas**: sem Xcode completo; qualquer dependência binária precisa resolver via SwiftPM com Command Line Tools
- **Escopo visual**: o visual clássico é um modo/skin; a biblioteca moderna não precisa parecer presa a 2001

## Key Decisions

| Decision | Rationale | Outcome |
|----------|-----------|---------|
| Swift + SwiftUI nativo em vez de Rust + Slint/Tauri | Foco em macOS, integração com AVFoundation/Now Playing e iteração rápida de UI | — Pending |
| SFBAudioEngine (MIT) como motor de reprodução, tags e ReplayGain | Decoders de muitos formatos, API Swift, mantido ativamente | ✓ Good (toca FLAC/M4A/WAV) |
| EQ via AVAudioUnitEQ entre `sourceNode` e `mainMixerNode` | SFB só permite alterar o grafo nesse trecho; o mixer deve continuar ligado à saída | ✓ Good (sem crash) |
| Não adicionar AudioKit por enquanto | Criaria um segundo motor de áudio redundante; EQ da Apple basta | — Pending |
| Frameworks LGPL embutidos como dinâmicos em `Contents/Frameworks` | Cumpre a LGPL mantendo-os substituíveis | — Pending |
| Sem sandbox; acesso a pastas centralizado em `LibraryRoot` (WineupCore) — fase 1 | App de distribuição direta; um ponto único facilita bookmarks e validação de caminhos | — Pending |
| Winamp/Mixxx/Cog só como referência de estudo | Licenças proíbem reutilização (WCL) ou exigem copyleft (GPL) | ✓ Good |
| "Singles" é um álbum virtual criado pelo app com faixas sem álbum e de álbuns de uma faixa | Pedido do usuário (2026-10-20); substitui "Álbum desconhecido" do briefing; nada é regravado nas tags | — Pending |
| Perfil do usuário exportável/importável (playlists, tags de cor, preferências, EQ) | Pedido do usuário: nunca perder o ecossistema montado | — Pending |
| `.planning/` versionado no git | Planejamento rastreável junto do código | — Pending |

## Evolution

This document evolves at phase transitions and milestone boundaries.

**After each phase transition** (via `/gsd-transition`):
1. Requirements invalidated? → Move to Out of Scope with reason
2. Requirements validated? → Move to Validated with phase reference
3. New requirements emerged? → Add to Active
4. Decisions to log? → Add to Key Decisions
5. "What This Is" still accurate? → Update if drifted

**After each milestone** (via `/gsd-complete-milestone`):
1. Full review of all sections
2. Core Value check — still the right priority?
3. Audit Out of Scope — reasons still valid?
4. Update Context with current state

---
*Last updated: 2026-10-19 after initialization*
