# Roadmap: Wineup Player

## Overview

Player de música nativo para macOS (Swift + SwiftUI) com interface clássica de painéis e o Wineup Library Fixer. O roadmap segue camadas horizontais (escolha do usuário), na ordem de dependência dos targets SwiftPM: Core, Dados, Áudio, Serviços, UI, Sistema, Fixer e Provedores online. Como o risco das camadas é entregar valor visível tarde, **toda fase termina com um build demonstrável (`swift build` + `.app`) em que o app ainda abre e toca**.

Granularidade: standard. Cobertura: 58/58 requisitos v1.

## Phases

- [x] **Phase 1: Fundação e Infraestrutura de Teste** - Núcleo `WineupCore` sem UI, IDs estáveis, `swift test` com Command Line Tools e build assinado de teste (completed 2026-10-20)
- [x] **Phase 2: Dados e Escrita Segura** - Biblioteca persistente em SQLite com varredura incremental, busca e infraestrutura de gravação de tags com backup, verificação e desfazer (completed 2026-10-20)
- [ ] **Phase 3: Áudio Real** - Espectro/VU reais, velocidade, balanço, EQ verificável, ReplayGain, gapless e troca de dispositivo
- [ ] **Phase 4: Serviços de Reprodução** - Fila, playlists, restauração de sessão e resolução de capas, tocando arquivos vindos do banco
- [ ] **Phase 5: Interface sobre Serviços Reais** - Painéis alimentados pelos serviços, navegação por discografia, letras sincronizadas, skins e acessibilidade
- [ ] **Phase 6: Integração com o Sistema e Distribuição** - Teclas de mídia, atalhos, modo mini, release assinado e notarizado em `.dmg`
- [ ] **Phase 7: Library Fixer v1 (offline)** - Diagnóstico, prévia com confiança, aplicação em lote e desfazer, edição simples de tags
- [ ] **Phase 8: Provedores Online e Fingerprint** - MusicBrainz, Cover Art Archive e AcoustID opcionais, com consentimento e modo offline padrão

## Phase Details

### Phase 1: Fundação e Infraestrutura de Teste
**Goal**: O código tem um núcleo testável separado da UI e o projeto prova cedo que testa e empacota com apenas Command Line Tools
**Depends on**: Nothing (first phase)
**Requirements**: FND-01, FND-02, FND-03, FND-04
**Success Criteria** (what must be TRUE):
  1. O app compila dividido em targets SwiftPM (com `WineupCore` sem dependência de UI), abre e toca FLAC/M4A/WAV como hoje
  2. `swift test` roda em um Mac só com Command Line Tools e executa testes do núcleo a cada build
  3. Reordenar ou filtrar a lista de faixas não muda a identidade delas: cada faixa mantém o mesmo identificador estável
  4. Um `.app` assinado de teste abre fora da pasta de build, com frameworks embutidos e rpath corretos
**Plans**: TBD
**Pesquisa de fase**: não (apenas spike de `swift test`)

### Phase 2: Dados e Escrita Segura
**Goal**: A biblioteca do usuário persiste entre sessões, é varrida e pesquisada com rapidez, e qualquer gravação de tag é protegida por backup, verificação e desfazer
**Depends on**: Phase 1
**Requirements**: LIB-01, LIB-02, LIB-03, LIB-04, LIB-05, LIB-06, LIB-07, SAFE-01, SAFE-02, SAFE-03, NAV-01
**Success Criteria** (what must be TRUE):
  1. Usuário adiciona pastas de música, fecha e reabre o app e as pastas e faixas continuam na biblioteca
  2. Uma nova varredura relê só arquivos novos ou alterados, mostra progresso e pode ser cancelada
  3. Arquivo movido, renomeado ou em disco desconectado aparece como ausente sem perder playlists e histórico
  4. Busca por título, artista ou álbum ignora acentos e responde instantaneamente em uma biblioteca sintética de 100 mil arquivos, sem travar a interface
  5. Gravar e reler tags em FLAC, MP3, M4A, Ogg/Opus e WAV preserva campos desconhecidos, versão de ID3 e capas; cada gravação tem backup, verificação e pode ser desfeita a partir do diário (validado por testes com arquivos de exemplo)
**Plans:** 6/6 plans complete
Plans:
- [x] 02-01-PLAN.md — GRDB/TagLib no pacote, esquema v1 (LIB-06, marcações, playlists), raízes persistentes e CatalogWriter
- [x] 02-02-PLAN.md — Scanner incremental, movidos/ausentes, escala de varredura
- [x] 02-03-PLAN.md — Busca FTS sem acento, navegação (Sem categoria, Singles), escala 100k
- [x] 02-04-PLAN.md — Backends de tags (SFB + TagLib ID3) e testes de preservação por formato
- [x] 02-05-PLAN.md — TagWriter seguro (backup, verificação, journal) e undo
- [x] 02-06-PLAN.md — NAV-01 (~/Music), integração no app e gate build-app
**Pesquisa de fase**: sim (cobertura de `writeMetadata` por formato, `replaceItemAt` e inode, backup por `clonefile`, sandbox/`LibraryRoot`)

### Phase 3: Áudio Real
**Goal**: O que o usuário vê e ouve reflete o áudio de verdade: medidores, velocidade, balanço, equalizador e ganho
**Depends on**: Phase 1 (pode se sobrepor à Phase 2)
**Requirements**: AUD-01, AUD-02, AUD-03, AUD-04, AUD-05, AUD-06, AUD-07
**Success Criteria** (what must be TRUE):
  1. Espectro e VU se movem conforme a música que toca e ficam parados em pausa ou silêncio
  2. Usuário muda a velocidade de reprodução e o tempo mostrado continua correto, e ajusta o balanço esquerda/direita de forma audível
  3. O equalizador de 10 bandas com preamp altera o áudio de forma verificável (render offline) e presets salvos voltam após reabrir o app
  4. ReplayGain de faixa/álbum muda o volume sem regravar o arquivo, e faixas consecutivas compatíveis tocam sem lacuna
  5. Trocar fones, AirPods ou HDMI durante a reprodução não interrompe nem trava o som
**Plans**: 6 plans
Plans:
- [ ] 03-01-PLAN.md — Target WineupAudio: EffectChain (TimePitch/EQ/balanço) e LevelTap testados em render offline
- [ ] 03-02-PLAN.md — Matemática pura em WineupCore (taxa, ReplayGain, EQ, espectro, próxima faixa) + porta AudioEngine
- [ ] 03-03-PLAN.md — Presets de EQ persistidos em app_setting
- [ ] 03-04-PLAN.md — SFBAudioEngineAdapter + ReplayGainReader + executável wineup-audiocheck
- [ ] 03-05-PLAN.md — App migra para o adaptador: velocidade, balanço, volume, RG, gapless, troca de dispositivo
- [ ] 03-06-PLAN.md — VU/espectro reais, presets e seletor de ReplayGain na UI
**UI hint**: yes
**Pesquisa de fase**: sim (risco alto: tap no grafo do SFB, ordem timePitch, EQ e pan, `currentTime` com taxa, gapless com EQ)

### Phase 4: Serviços de Reprodução
**Goal**: A reprodução passa a funcionar sobre a biblioteca persistente, com fila, playlists e sessão restaurável
**Depends on**: Phase 2, Phase 3
**Requirements**: PLAY-01, PLAY-02, PLAY-03, PLAY-04, DISC-02, NAV-03, PROF-01, PROF-02
**Success Criteria** (what must be TRUE):
  1. Usuário toca uma faixa vinda da biblioteca persistente de ponta a ponta, monta uma fila, reordena, repete (uma/todas) e embaralha
  2. Usuário cria, salva, renomeia e apaga playlists e importa/exporta M3U/M3U8
  3. Ao reabrir o app, a fila, a faixa e a posição da última sessão voltam
  4. "Reproduzir tudo" de um artista não repete a mesma gravação lançada como single e álbum (configurável)
  5. A capa exibida segue a ordem arte do arquivo, imagem na pasta, capa do lançamento, placeholder, sem gravar nos arquivos
**Plans**: TBD
**Pesquisa de fase**: não

### Phase 5: Interface sobre Serviços Reais
**Goal**: Os painéis clássicos mostram e controlam dados reais, com navegação por discografia, letras sincronizadas, skins próprias e acessibilidade
**Depends on**: Phase 4
**Requirements**: UI-01, UI-02, UI-03, UI-04, UI-05, DISC-01, DISC-03, DISC-04, NAV-02, NAV-04
**Success Criteria** (what must be TRUE):
  1. Os painéis AMP, FX, Playlist, Search, Lyrics e Capa refletem a reprodução, a biblioteca e os medidores reais
  2. Usuário abre a página de um artista e vê álbuns, EPs, singles e "Álbum desconhecido" sem que nenhuma tag seja reescrita, e reproduz tudo ou embaralha com a ordenação ativa visível
  3. Letras embutidas e arquivos `.lrc` aparecem, com a linha atual destacada em sincronia quando há tempo
  4. Grafite, Vinho e Verde funcionam como skins embutidas de um formato próprio documentado
  5. Sliders, botões e listas customizados podem ser usados com VoiceOver e teclado, e disposição, tema e tamanho de janela persistem entre sessões
**Plans**: TBD
**UI hint**: yes
**Pesquisa de fase**: não

### Phase 6: Integração com o Sistema e Distribuição
**Goal**: O app se comporta como cidadão do macOS e pode ser distribuído e aberto em um Mac limpo
**Depends on**: Phase 5
**Requirements**: SYS-01, SYS-02, SYS-03, SYS-04, SYS-05
**Success Criteria** (what must be TRUE):
  1. Teclas de mídia, Central de Controle e tela de bloqueio controlam a reprodução e mostram a faixa atual
  2. Os atalhos clássicos (Z X C V B, espaço, setas) controlam o player
  3. O modo mini fica sempre no topo
  4. O script de release gera um `.dmg` assinado com Developer ID e notarizado que abre num Mac limpo (VM tart)
  5. Os avisos de terceiros listam versões exatas e as bibliotecas LGPL continuam substituíveis dentro do `.app`
**Plans**: TBD
**UI hint**: yes
**Pesquisa de fase**: sim (`notarytool` nos CLT, Developer ID, validação de bibliotecas LGPL, MPRemoteCommandCenter em `.app` montado por script)

### Phase 7: Library Fixer v1 (offline)
**Goal**: Usuário corrige tags, capas e duplicatas da biblioteca com prévia, confiança explicada e desfazer, sem risco aos arquivos
**Depends on**: Phase 2 (escrita segura), Phase 5 (UI)
**Requirements**: SAFE-04, FIX-01, FIX-02, FIX-03, FIX-04, FIX-05, FIX-06, FIX-07
**Success Criteria** (what must be TRUE):
  1. Usuário escolhe pastas e o Fixer diagnostica sem gravar nada: tags ausentes/inconsistentes, capa ausente ou pequena, `.lrc` órfão e duplicatas idênticas
  2. Cada correção proposta mostra origem, confiança por campo e o diff antes/depois; usuário aceita tudo, escolhe correções específicas ou corrige manualmente
  3. Correção de baixa confiança nunca sobrescreve um campo já preenchido, e um problema ignorado não reaparece nas próximas análises
  4. Usuário edita tags simples de uma ou várias faixas com prévia antes de gravar
  5. Um lote aplicado pode ser desfeito por inteiro; duplicatas só são relatadas e remover exige confirmação e vai para a Lixeira
**Plans**: TBD
**UI hint**: yes
**Pesquisa de fase**: sim (regras de diagnóstico e pesos de confiança)

### Phase 8: Provedores Online e Fingerprint
**Goal**: Usuário pode, por escolha própria, enriquecer a biblioteca com metadados e capas online, com privacidade e limites respeitados
**Depends on**: Phase 7
**Requirements**: NET-01, NET-02, NET-03, NET-04, NET-05
**Success Criteria** (what must be TRUE):
  1. O app inicia offline; usuário liga, por provedor, consultas a MusicBrainz e Cover Art Archive
  2. Antes do primeiro envio, o app mostra exatamente o que será enviado e pede consentimento
  3. Identificação por impressão acústica sugere o lançamento com confiança, considerando duração e contexto do álbum
  4. O Fixer busca capas online e o usuário escolhe entre embutir no arquivo ou salvar ao lado
  5. Requisições respeitam os limites de cada serviço e podem ser interrompidas e retomadas
**Plans**: TBD
**UI hint**: yes
**Pesquisa de fase**: sim (Chromaprint com CLT e licença, termos de MusicBrainz/AcoustID/CAA)

## Progress

| Fase | Planos concluídos | Status | Concluída |
|------|-------------------|--------|-----------|
| 1. Fundação e Infraestrutura de Teste | 3/3 | Complete    | 2026-10-20 |
| 2. Dados e Escrita Segura | 6/6 | Complete    | 2026-10-20 |
| 3. Áudio Real | 0/0 | Não iniciada | - |
| 4. Serviços de Reprodução | 0/0 | Não iniciada | - |
| 5. Interface sobre Serviços Reais | 0/0 | Não iniciada | - |
| 6. Integração com o Sistema e Distribuição | 0/0 | Não iniciada | - |
| 7. Library Fixer v1 (offline) | 0/0 | Não iniciada | - |
| 8. Provedores Online e Fingerprint | 0/0 | Não iniciada | - |
