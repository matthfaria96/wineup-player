# Estado do Projeto

## Referência do Projeto

Ver: .planning/PROJECT.md (atualizado em 2026-10-19)

**Valor central:** Tocar a biblioteca local do usuário de forma confiável, com a interface clássica de painéis, e nunca danificar os arquivos dele.
**Foco atual:** Estabilizar e testar antes do primeiro release (o usuário pediu para NÃO publicar ainda).

## Posição Atual

As fases 1 a 3 foram feitas pelo fluxo GSD (planos em `phases/`). Depois disso o trabalho seguiu por pedidos
diretos do usuário, fora dos planos, e entregou na prática quase tudo das fases 4, 5, 7 e 8 e parte da 6:

| Fase | Situação real | O que falta |
|------|---------------|-------------|
| 4. Serviços de Reprodução | Entregue (fila, playlists, sessão, capas) direto no app | — |
| 5. Interface sobre Serviços Reais | Entregue: painéis, discografia, letras sincronizadas, skins próprias, dicas ao passar o mouse | — |
| 6. Integração e Distribuição | Parcial: teclas de mídia, atalhos, player na barra de menus | Release assinado, notarizado e em `.dmg` |
| 7. Library Fixer v1 | Entregue como janela "Metadados" (diagnóstico, prévia, lote, desfazer, edição) | — |
| 8. Provedores Online | Entregue: MusicBrainz, Cover Art Archive, iTunes, letras online, AcoustID opcional, consentimento | — |

Última atividade: 2026-10-24 — revisão geral de desempenho, traduções e limpeza da tela de Metadados.

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
- Não publicar (GitHub/site) até o usuário pedir

### Pendências

- O usuário vai testar: troca de idioma + Reabrir, faixa de aprovação e Escolher resultado nos Metadados,
  dicas ao passar o mouse, repetir uma, retomar sessão, pulo de arquivo corrompido
- Revisão nativa das traduções além de inglês e espanhol
- Release: versão (ainda 0.1.0), assinatura, notarização, `.dmg`, página no witchmymac.com

### Bloqueios/Preocupações

- Nenhum bloqueio. Capturas de tela: usar `WINEUP_OPEN_WINDOW` e `WINEUP_TEST_SCREEN=left` com `open -g`
  para não tirar o foco do usuário.

## Continuidade da Sessão

Última sessão: 2026-10-24
Parou em: correções finais pedidas pelo usuário; aguardando os testes dele antes de qualquer release.
