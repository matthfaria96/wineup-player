# Requirements — Wineup Player

**Defined:** 2026-10-20
**Core Value:** Tocar a biblioteca local do usuário de forma confiável, com a interface clássica de painéis, e nunca danificar os arquivos dele.

## v1 Requirements

### Fundação (FND)

- [x] **FND-01**: O código é dividido em targets SwiftPM com um núcleo (`WineupCore`) sem dependência de UI, e o app continua abrindo e tocando como hoje
- [x] **FND-02**: `swift test` roda só com Command Line Tools e executa testes do núcleo em cada build
- [x] **FND-03**: Faixas têm identificador estável (não baseado em posição na lista)
- [x] **FND-04**: Um build assinado de teste valida empacotamento (rpath, frameworks embutidos) cedo no projeto

### Biblioteca (LIB)

- [x] **LIB-01**: Usuário adiciona pastas de música como raízes da biblioteca e elas persistem entre sessões
- [x] **LIB-02**: A biblioteca é varrida de forma incremental (só arquivos novos/alterados são relidos) com progresso e cancelamento
- [x] **LIB-03**: Arquivos movidos, renomeados ou em disco desconectado aparecem como ausentes, sem perder playlists e histórico
- [x] **LIB-04**: Usuário busca por título, artista ou álbum (ignorando acentos) com resultado instantâneo em bibliotecas grandes
- [x] **LIB-05**: Usuário navega por artista, álbum, gênero, pasta e todas as faixas
- [x] **LIB-06**: O modelo distingue arquivo, gravação, faixa no lançamento, lançamento, artista, arte e letra
- [x] **LIB-07**: Uma biblioteca sintética de 100 mil arquivos é varrida e pesquisada sem travar a interface

### Escrita segura (SAFE)

- [x] **SAFE-01**: Toda gravação de tag passa por um único gravador que faz backup antes, verifica depois e registra no diário
- [x] **SAFE-02**: Toda gravação pode ser desfeita a partir do diário
- [x] **SAFE-03**: Gravar e reler tags preserva campos desconhecidos, versão de ID3 e capas em FLAC, MP3, M4A, Ogg/Opus e WAV (testado com arquivos de exemplo)
- [ ] **SAFE-04**: Usuário edita tags simples (título, artista, álbum, faixa, ano, gênero) de uma ou várias faixas, com prévia antes de gravar

### Áudio (AUD)

- [ ] **AUD-01**: Espectro e medidor de nível (VU) refletem o áudio que está tocando
- [ ] **AUD-02**: Usuário muda a velocidade de reprodução e o tempo/letras continuam sincronizados
- [ ] **AUD-03**: Usuário ajusta o balanço esquerda/direita
- [ ] **AUD-04**: Equalizador de 10 bandas + preamp altera o áudio de forma verificável, com presets salvos pelo usuário
- [ ] **AUD-05**: ReplayGain (faixa/álbum) é aplicado como ganho, sem regravar o áudio
- [ ] **AUD-06**: Faixas consecutivas tocam sem lacuna (gapless) quando o formato permite
- [ ] **AUD-07**: Trocar o dispositivo de saída (fones, AirPods, HDMI) não interrompe nem trava a reprodução

### Reprodução e fila (PLAY)

- [ ] **PLAY-01**: Usuário monta uma fila, reordena, repete (uma/todas) e embaralha
- [ ] **PLAY-02**: Usuário cria, salva, renomeia e apaga playlists, e importa/exporta M3U/M3U8
- [ ] **PLAY-03**: Ao reabrir o app, a fila, a faixa e a posição da última sessão são restauradas
- [ ] **PLAY-04**: "Reproduzir tudo" de um artista evita repetir a mesma gravação lançada em single e álbum (configurável)

### Discografia, capas e letras (DISC)

- [ ] **DISC-01**: Página do artista mostra álbuns, EPs e o álbum "Singles" do app como visões, sem reescrever tags
- [ ] **DISC-02**: A capa exibida segue a ordem: arte do arquivo, imagem na pasta, capa do lançamento, placeholder — sem gravar nos arquivos
- [ ] **DISC-03**: Letras embutidas e arquivos `.lrc` são exibidos, com destaque sincronizado quando houver tempo
- [ ] **DISC-04**: Usuário reproduz tudo ou embaralha a partir da página do artista, com a ordenação ativa visível

### Navegação da biblioteca (NAV)

- [x] **NAV-01**: Na primeira abertura, o app adiciona e carrega automaticamente a pasta Música do usuário (`~/Music`) como raiz da biblioteca
- [ ] **NAV-02**: Usuário escolhe como ver a biblioteca: por Álbum, por Banda/Artista, por Pastas, por Estilo (gênero dos metadados; faixas sem gênero ficam em "Sem categoria") ou por Playlists
- [ ] **NAV-03**: Na visão por Álbum, faixas sem álbum e faixas de álbuns com uma única música aparecem num álbum "Singles" criado pelo app (agrupamento virtual, sem reescrever tags)
- [ ] **NAV-04**: Na visão de Playlists aparecem as playlists do usuário e uma playlist automática por cor de tag, exibida só quando há ao menos uma faixa com aquela cor; uma opção desativa as playlists de tags

### Perfil do usuário (PROF)

- [ ] **PROF-01**: Playlists, cores de tag atribuídas às faixas, preferências de exibição e presets de EQ ficam salvos num perfil do usuário persistido automaticamente
- [ ] **PROF-02**: Usuário exporta o perfil para um arquivo e importa um perfil (em outro Mac ou após reinstalar), com prévia do que será importado, sem perder o ecossistema montado

### Interface (UI)

- [ ] **UI-01**: Os painéis atuais (AMP, FX, Playlist, Search, Lyrics, Capa) passam a ser alimentados pelos serviços reais
- [ ] **UI-02**: Temas são definidos por um formato de skin próprio documentado; Grafite, Vinho e Verde viram skins embutidas
- [ ] **UI-03**: Os controles customizados (sliders, botões, listas) funcionam com VoiceOver e teclado
- [ ] **UI-04**: Disposição, tema e tamanho de janela persistem entre sessões
- [ ] **UI-05**: Usuário altera o design de exibição da janela e do conteúdo (disposição dos painéis, tema/skin e estilo da lista: compacta, com capas ou em grade) num seletor de exibição

### Sistema e distribuição (SYS)

- [ ] **SYS-01**: Teclas de mídia, Central de Controle e tela de bloqueio controlam a reprodução e mostram a faixa atual
- [ ] **SYS-02**: Atalhos de teclado clássicos (Z X C V B, espaço, setas) controlam o player
- [ ] **SYS-03**: Modo mini sempre no topo
- [ ] **SYS-04**: Script de release assina com Developer ID, notariza e gera `.dmg` que abre num Mac limpo
- [ ] **SYS-05**: Avisos de terceiros listam versões exatas e as bibliotecas LGPL continuam substituíveis no `.app`

### Library Fixer (FIX)

- [ ] **FIX-01**: Usuário escolhe pastas e o Fixer diagnostica, sem gravar nada: tags ausentes/inconsistentes, capa ausente ou pequena, `.lrc` órfão, duplicatas idênticas
- [ ] **FIX-02**: Cada correção proposta mostra origem, confiança por campo e o diff antes/depois
- [ ] **FIX-03**: Usuário aceita tudo, escolhe correções específicas ou corrige manualmente
- [ ] **FIX-04**: Correção de baixa confiança nunca sobrescreve um campo já preenchido
- [ ] **FIX-05**: Usuário ignora um problema e ele não reaparece nas próximas análises
- [ ] **FIX-06**: Um lote aplicado pode ser desfeito por inteiro
- [ ] **FIX-07**: Duplicatas são só relatadas; remover exige confirmação e vai para a Lixeira

### Provedores online (NET)

- [ ] **NET-01**: Usuário liga, por provedor, consultas a MusicBrainz/Cover Art Archive; o padrão é offline
- [ ] **NET-02**: Antes do primeiro envio, o app mostra exatamente o que será enviado e pede consentimento
- [ ] **NET-03**: Identificação por impressão acústica (AcoustID/Chromaprint) sugere o lançamento com confiança, considerando duração e contexto do álbum
- [ ] **NET-04**: Fixer busca capas online e permite escolher entre embutir no arquivo ou salvar ao lado
- [ ] **NET-05**: Requisições respeitam os limites de cada serviço e podem ser interrompidas e retomadas

## v2 Requirements

### Skins clássicas

- **WSZ-01**: Importar um subconjunto declarado de skins clássicas `.wsz`
- **WSZ-02**: Formato de preset de EQ `.eqf`

### Organização

- **ORG-01**: Renomear/mover arquivos por política configurável, com prévia e desfazer
- **ORG-02**: Detecção de versões distintas (ao vivo, remix, regravação) além de cópias idênticas

### Extras

- **EXT-01**: Visualizações avançadas (estilo MilkDrop)
- **EXT-02**: Painéis destacáveis em janelas separadas
- **EXT-03**: Atualização automática (Sparkle)
- **EXT-04**: Busca de letras online, se houver provedor com termos compatíveis
- **EXT-05**: Versão Windows

## Out of Scope

| Feature | Reason |
|---------|--------|
| Plugins do Winamp (DLL) | Windows-only e incompatível com o app nativo |
| Código do Winamp, Mixxx, Cog ou componentes sem licença | WCL proíbe; GPL exige copyleft; sem licença = todos os direitos reservados |
| Contornar licença de apps de terceiros (AMP) | Só referência de comportamento observável |
| Streaming, podcasts, loja | Foco em biblioteca local |
| Scrobbling ligado por padrão / telemetria | Privacidade |
| Correção automática silenciosa e remoção automática de duplicatas | Viola o Core Value |
| Normalização que regrava o áudio | Só ReplayGain não destrutivo |
| "Singles" como álbum real gravado nas tags | Singles é visão virtual |
| DJ, ripper, editor de áudio | Fora do produto |

## Traceability

| Requirement | Phase | Status |
|-------------|-------|--------|
| FND-01 | Fase 1 | Pendente |
| FND-02 | Fase 1 | Pendente |
| FND-03 | Fase 1 | Pendente |
| FND-04 | Fase 1 | Pendente |
| LIB-01 | Fase 2 | Pendente |
| LIB-02 | Fase 2 | Pendente |
| LIB-03 | Fase 2 | Pendente |
| LIB-04 | Fase 2 | Pendente |
| LIB-05 | Fase 2 | Pendente |
| LIB-06 | Fase 2 | Pendente |
| LIB-07 | Fase 2 | Pendente |
| SAFE-01 | Fase 2 | Pendente |
| SAFE-02 | Fase 2 | Pendente |
| SAFE-03 | Fase 2 | Pendente |
| SAFE-04 | Fase 7 | Pendente |
| AUD-01 | Fase 3 | Pendente |
| AUD-02 | Fase 3 | Pendente |
| AUD-03 | Fase 3 | Pendente |
| AUD-04 | Fase 3 | Pendente |
| AUD-05 | Fase 3 | Pendente |
| AUD-06 | Fase 3 | Pendente |
| AUD-07 | Fase 3 | Pendente |
| PLAY-01 | Fase 4 | Pendente |
| PLAY-02 | Fase 4 | Pendente |
| PLAY-03 | Fase 4 | Pendente |
| PLAY-04 | Fase 4 | Pendente |
| DISC-01 | Fase 5 | Pendente |
| DISC-02 | Fase 4 | Pendente |
| DISC-03 | Fase 5 | Pendente |
| DISC-04 | Fase 5 | Pendente |
| UI-01 | Fase 5 | Pendente |
| UI-02 | Fase 5 | Pendente |
| UI-03 | Fase 5 | Pendente |
| UI-04 | Fase 5 | Pendente |
| NAV-01 | Fase 2 | Pendente |
| NAV-02 | Fase 5 | Pendente |
| NAV-03 | Fase 4 | Pendente |
| NAV-04 | Fase 5 | Pendente |
| PROF-01 | Fase 4 | Pendente |
| PROF-02 | Fase 4 | Pendente |
| UI-05 | Fase 5 | Pendente |
| SYS-01 | Fase 6 | Pendente |
| SYS-02 | Fase 6 | Pendente |
| SYS-03 | Fase 6 | Pendente |
| SYS-04 | Fase 6 | Pendente |
| SYS-05 | Fase 6 | Pendente |
| FIX-01 | Fase 7 | Pendente |
| FIX-02 | Fase 7 | Pendente |
| FIX-03 | Fase 7 | Pendente |
| FIX-04 | Fase 7 | Pendente |
| FIX-05 | Fase 7 | Pendente |
| FIX-06 | Fase 7 | Pendente |
| FIX-07 | Fase 7 | Pendente |
| NET-01 | Fase 8 | Pendente |
| NET-02 | Fase 8 | Pendente |
| NET-03 | Fase 8 | Pendente |
| NET-04 | Fase 8 | Pendente |
| NET-05 | Fase 8 | Pendente |

**Coverage:**
- v1 requirements: 58 total
- Mapped to phases: 58
- Unmapped: 0

---
*Requirements defined: 2026-10-20*
*Last updated: 2026-10-20 after initial definition*

*2026-10-20: adicionados NAV-01..04, PROF-01..02, UI-05 a pedido do usuário; DISC-01 passa a usar o álbum "Singles" do app.*
