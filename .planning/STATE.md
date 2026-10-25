# Estado do Projeto

## Referência do Projeto

Ver: .planning/PROJECT.md (atualizado em 2026-10-19)

**Valor central:** Tocar a biblioteca local do usuário de forma confiável, com a interface clássica de painéis, e nunca danificar os arquivos dele.
**Foco atual:** 1.0.0 pronta para o primeiro release público (o coordenador publica no GitHub e no witchmymac.com).

## Posição Atual

As fases 1 a 3 foram feitas pelo fluxo GSD (planos em `phases/`). Depois disso o trabalho seguiu por pedidos
diretos do usuário, fora dos planos, e entregou na prática quase tudo das fases 4, 5, 7 e 8 e parte da 6:

| Fase | Situação real | O que falta |
|------|---------------|-------------|
| 4. Serviços de Reprodução | Entregue (fila, playlists, sessão, capas) direto no app | — |
| 5. Interface sobre Serviços Reais | Entregue: painéis, discografia, letras sincronizadas, skins próprias, dicas ao passar o mouse | — |
| 6. Integração e Distribuição | Entregue com assinatura ad-hoc: universal, `.dmg` via make-dmg.sh, README en/pt-BR | Developer ID + notarização (SYS-04) quando houver certificado |
| 7. Library Fixer v1 | Entregue como janela "Metadados" (diagnóstico, prévia, lote, desfazer, edição) | — |
| 8. Provedores Online | Entregue: MusicBrainz, Cover Art Archive, iTunes, letras online, AcoustID opcional, consentimento | — |

Última atividade: 2026-10-24 — preparação do 1.0.0 (ícone, versão, build universal, README, correções visuais).

## Release 1.0.0 (2026-10-24, tag v1.0.0)

- Versão 1.0.0 (build 2) em `scripts/build-app.sh` (VERSION/BUILD) e `WineupCore.version`.
- Build universal (arm64 + x86_64) por padrão; `UNIVERSAL=0` para build nativo rápido. Mínimo macOS 14.
- Ícone refeito por `scripts/make-icon.swift`: superelipse n=5, corpo 824/1024 (antes era quadrado cheio).
- `verify-app.sh` abre o app em segundo plano, mudo e com biblioteca temporária (`VERIFY_LAUNCH=0` não abre);
  `smoke-playback.sh` só encerra a própria instância.
- Correções: sessão retomada também quando a biblioteca abre em Artistas/Álbuns/Estilos/Playlists; estilo
  Grade mostra álbuns/artistas como capas; janela Compacta com 980 pt de altura; caminho `~/…` nos Metadados;
  "Em uso" legível na lista de Skins; fada do PixelArt fora do contador.
- Licenças: clipe de Nova York removido (sem fonte/licença registrada); Méliès e fontes VT323/Press Start 2P
  creditados em THIRD_PARTY_NOTICES. Licença do app: GPL-3.0.
- Testes de tela sem atrapalhar o usuário: cópia com bundle id `app.wineup.player.check`,
  `CFFIXED_USER_HOME=<pasta>` isola Application Support e ~/Music, `open -g -n`, captura `screencapture -l`.
  Não rodar `scripts/ui-test.sh` (cliques reais) com o usuário no Mac.

## Feito em 2026-10-23/24 (commits d52d1d2 … 5deacb6 e seguintes)

- Desempenho e travamentos: Metadados (salvar/desfazer/lixeira fora da thread principal, índices, cache),
  janela principal (PlayerState dividido em modelos pequenos, temas e busca em cache, animações pausam com a
  janela oculta), áudio (falhas de leitura pulam a faixa, seek no início para CUE/sessão, medição de volume só
  com a Correção de Som, repetir uma, motor para no fim).
- EQ: presets suaves com descrição e limitador de pico da Apple; Correção de Som por EBU R128.
- Skins: ordem Musical, Retro, PixelArt, Sci-Fi, Neon Gótico, Emoboy (Noite Estrelada removida).
- Traduções: 16 idiomas + pt-BR (`scripts/l10n-extract.sh`, `scripts/l10n.py`, `Localization/*.json`),
  idioma escolhido em Ajustes › Geral (padrão: Sistema).
- Ajustes (⌘,) no padrão do MacDash; dicas `.hint` em toda a tela principal.
- Metadados: barra enxuta (Corrigir tudo, Buscar, Histórico, Opções, Mostrar), faixa de aprovação com
  "prontas para salvar" e "para revisar", filtro Para revisar, botão Escolher resultado….
- Removido código morto: módulo `WineupServices` (PlaybackController/SessionStore não eram usados).
- Músicas de demonstração apagadas a pedido; o usuário usa a própria pasta ~/Music.

## Contexto Acumulado

### Decisões

- Camadas horizontais, com build demonstrável e app tocando ao fim de cada fase
- Sem sandbox, Developer ID + hardened runtime; acesso a pastas atrás de `LibraryRoot`
- Escrita segura (backup, journal, verificação) antes de qualquer gravação de tags
- Swift Testing; testes com `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/test.sh`
- Texto em português do código é a chave de tradução; todo texto novo de tela precisa ser traduzível
- Publicação do 1.0.0 liberada pelo usuário (coordenador cuida do GitHub e do site)

### Pendências

- O usuário vai testar: troca de idioma + Reabrir, faixa de aprovação e Escolher resultado nos Metadados,
  dicas ao passar o mouse, repetir uma, retomar sessão, pulo de arquivo corrompido
- Revisão nativa das traduções além de inglês e espanhol
- Developer ID + notarização (SYS-04) e ShazamKit quando houver certificado
- Confirmar a origem das ilustrações dos skins Musical, Retro e PixelArt para os créditos

### Bloqueios/Preocupações

- Nenhum bloqueio. Capturas de tela: usar `WINEUP_OPEN_WINDOW` e `WINEUP_TEST_SCREEN=left` com `open -g`
  para não tirar o foco do usuário.

## Continuidade da Sessão

Última sessão: 2026-10-24
Parou em: 1.0.0 empacotada (DMG WineupPlayer-1.0.0); publicação fica com o coordenador.
