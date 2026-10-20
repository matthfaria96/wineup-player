# Panorama de Funcionalidades

**Domínio:** player de música local para macOS, estilo Winamp, com "Library Fixer" integrado
**Pesquisado em:** 2026-10-19
**Confiança geral:** MEDIUM. Baseado em conhecimento do domínio (Picard, OneTagger, foobar2000, Cog, Audacious, Swinsian, Doppler, Vox) e no briefing do projeto. Não houve verificação web nesta rodada; itens marcados (LOW) precisam de validação antes de virarem requisito.

## Table Stakes

Sem isso o usuário abandona o app. Itens já validados no protótipo estão marcados.

| Funcionalidade | Por que é esperada | Complexidade | Notas |
|---|---|---|---|
| Reprodução FLAC/M4A/WAV/MP3 + play/pause/stop/seek/volume (já existe) | Núcleo de qualquer player | Baixa | Conferir MP3, OGG, Opus, ALAC, AIFF via SFBAudioEngine |
| Reprodução sem lacuna (gapless) | Álbuns ao vivo/conceituais; Swinsian, foobar2000, Cog e Doppler fazem | Média | Exige pré-agendar a próxima faixa no mesmo grafo do AVAudioEngine |
| Biblioteca persistente com varredura incremental | Swinsian/Doppler/Vox: biblioteca sobrevive ao reinício | Alta | SQLite; detectar arquivos movidos/ausentes; FSEvents para pastas observadas |
| Navegação por artista/álbum/faixa/gênero/pastas | Padrão em todos os gerenciadores | Média | Depende do modelo de dados |
| Busca instantânea (título/artista/álbum) | Esperada; Winamp tinha Jump to File (J) | Baixa | FTS5 do SQLite |
| Playlists salvas, fila ("tocar a seguir"/"adicionar à fila"), repetir/embaralhar | Básico | Média | Importar/exportar M3U/M3U8; playlists devem tolerar arquivos ausentes |
| Restaurar estado (faixa, posição, layout, janelas) | Usuários de Winamp esperam | Baixa | |
| Teclas de mídia, Now Playing (Central de Controle), MPRemoteCommandCenter | Obrigatório no macOS; Vox/Doppler/Swinsian têm | Média | Atualizar capa, título, posição; sem Xcode completo, usar MediaPlayer via SwiftPM |
| Atalhos de teclado (inclusive os clássicos Z X C V B) | Identidade Winamp + acessibilidade | Baixa | Atalhos globais opcionais (exigem permissão) |
| Capa em arquivo/embutida, com fallback visual | Todos exibem; regras do briefing | Média | Ordem: capa embutida válida, depois cover.jpg/folder.jpg na pasta, depois capa do lançamento (sem gravar), depois placeholder |
| Letras embutidas e `.lrc` sincronizadas (destaque da linha, clique para saltar) | Esperado em players atuais | Média | Parser LRC tolerante (offsets `[offset:]`, tags de palavra enhanced opcionais); prioridade `.lrc` ao lado do arquivo, depois embutida |
| EQ 10 bandas com presets nomeados e persistentes (+ preamp) | Marca registrada do Winamp | Baixa | Importar `.eqf` do Winamp é barato e nostálgico (LOW, validar formato) |
| Velocidade de reprodução e balanço reais | Já na UI, hoje só visuais | Baixa | Evitar controles que não fazem nada |
| Espectro e VU reais | Winamp sem visualização parece quebrado | Média | Tap no mixer + FFT (Accelerate/vDSP); simulado hoje é dívida |
| Arrastar e soltar, "Abrir com", associação de arquivos (já existe) | Básico | Baixa | |
| Metadados editáveis simples (editar tags de uma faixa) | Swinsian/foobar2000 têm; Library Fixer precisa da base | Média | Passa pelo mesmo pipeline seguro de escrita do Fixer |
| ReplayGain não destrutivo (ler tags, aplicar ganho) | Esperado por quem tem biblioteca grande; foobar2000/Cog/Audacious | Média | SFBAudioEngine lê/calcula; aplicar como ganho de reprodução, nunca regravar amostras |
| Modo mini (janela compacta sempre no topo) | Winamp "windowshade" é parte da identidade | Média | Pode ser o layout Compacto atual + opção "sempre no topo" |
| Acessibilidade (VoiceOver, navegação por teclado, contraste) | Briefing exige; UI customizada de painéis costuma falhar | Média | Fazer desde o início nos controles customizados |

## Diferenciais

| Funcionalidade | Proposta de valor | Complexidade | Notas |
|---|---|---|---|
| Library Fixer em assistente: pastas, análise, prévia, aceitar tudo/seletivo/manual, aplicar, desfazer | Picard/OneTagger exigem expertise e não são players; aqui é integrado e seguro | Alta | Diferencial principal. Diff por campo, origem e confiança visíveis |
| Nível de confiança explicado (alto/médio/baixo com motivo) | Picard mostra similaridade só em número; aqui explica | Média | Regra dura: nunca sobrescrever dado bom com resultado de baixa confiança; baixa confiança só aparece como sugestão |
| Desfazer real (diário de alterações + backup de tags antes da escrita) | Nenhum player concorrente oferece rollback | Alta | Journal em SQLite com valores antigos; backup de arquivo opcional; desfazer por lote. Separar tags, renomeação e áudio |
| Discografia por artista com Singles/EP/Álbum desconhecido como visões virtuais | Swinsian/Vox agrupam só por tag Album; aqui há "Singles" sem reescrever tags | Alta | Classificação: tipo vindo de MusicBrainz/tags (RELEASETYPE), ou heurística rotulada com confiança; "desconhecido" nunca vira single por suposição |
| Reproduzir tudo / Embaralhar do artista com ordem configurável e dedup single↔álbum na fila | Evita ouvir a mesma gravação duas vezes | Alta | Comparar duração, IDs (MBID/ISRC), fingerprint; não tratar remix/ao vivo como duplicata. Depende do modelo gravação vs faixa |
| Detecção de duplicatas: cópia idêntica vs versão distinta | Cleaners comuns apagam por nome/hash; aqui há semântica | Alta | Camadas: hash do arquivo, depois fingerprint, depois duração/tags; só relatório, nunca remoção automática |
| Escolha de capa com origem/confiança e várias candidatas | Picard grava a primeira; aqui o usuário escolhe | Média | Capa do lançamento só como fallback visual por padrão; embutir é ação explícita do Fixer |
| Reconhecimento por impressão acústica (AcoustID/Chromaprint) + MusicBrainz | Corrige faixas sem tag | Alta | Opcional, aviso do que é enviado, modo offline. Chromaprint é LGPL/MIT conforme o componente (LOW, auditar); rate limit do MusicBrainz 1 req/s |
| Skins próprias (formato documentado) e temas | Identidade; Winamp = skins | Média | Leitura de `.wsz`: escopo limitado a skins de main/EQ/playlist (bitmaps), sem promessa de compatibilidade (alta complexidade, adiar) |
| Visualizações além de espectro (osciloscópio, barras estilo Winamp) | Nostalgia | Média | MilkDrop/projectM é GPL: só reescrever ideias, não copiar |
| Janela de painéis destacáveis (cada painel como janela clássica, encaixe magnético) | Experiência Winamp autêntica | Média | Estende os 3 layouts atuais |
| Painel de saúde da biblioteca (contagem de problemas por tipo, sem aplicar nada) | Torna o Fixer descobrível | Baixa | Barato depois do diagnóstico |
| Modo offline explícito e painel de privacidade | Alinha com sem telemetria | Baixa | Mostrar payload antes de enviar |

## Anti-Funcionalidades

| Anti-funcionalidade | Por que evitar | O que fazer no lugar |
|---|---|---|
| Correção automática silenciosa de tags em segundo plano | Viola "nunca danificar arquivos" | Sempre prévia e confirmação; sem aplicar ao abrir a biblioteca |
| Reescrever a tag Album para criar "Singles" | Briefing proíbe | Visão virtual no banco |
| Apagar duplicatas automaticamente | Perda de dados irreversível | Relatório, mover para Lixeira só com confirmação e registro |
| Normalização que regrava amostras | Destrutivo | ReplayGain por tag + ganho em tempo real |
| Renomear/mover arquivos por padrão | Quebra playlists e backups do usuário | Etapa opcional separada, com prévia |
| Gravar resultado de baixa confiança | Corrompe dado bom | Mostrar como sugestão ignorável |
| Streaming/serviços online, rádio, podcasts, loja | Foge do foco em biblioteca local; custo alto | Foco local; talvez abrir URL M3U depois |
| Scrobbling/contas/telemetria por padrão | Privacidade | Scrobbling Last.fm opcional e tardio, se pedido |
| Suporte a plugins nativos do Winamp (DLLs) | Impossível no macOS, licença WCL | Documentar como fora de escopo |
| Compatibilidade total com `.wsz` e modernas skins (Modern Skins/Freeform) | Custo enorme, promessa falsa | Subconjunto clássico declarado |
| Copiar código do Winamp, Mixxx, Cog, projectM | Licenças | Reescrever; LGPL só por linkagem dinâmica |
| Editor de áudio, DJ, ripper de CD, conversor | Deixa de ser player | Ficar fora |
| Sincronização iCloud/iPhone, apps móveis | Escopo | Não agora |
| Biblioteca presa ao visual 2001 | Briefing: biblioteca moderna pode ser moderna | Skin retrô é modo, não limitação |

## Dependências entre Funcionalidades

```
Modelo de dados (arquivo/gravação/lançamento/artista/arte/letra) -> Biblioteca SQLite -> Navegação por artista/álbum/single
Biblioteca SQLite -> Busca FTS, playlists, restaurar estado, painel de saúde
Modelo gravação vs faixa -> Dedup single<->álbum na fila -> Reproduzir tudo do artista
Pipeline seguro de escrita de tags (backup + journal) -> Edição simples de tags -> Library Fixer -> Desfazer
Diagnóstico offline (tags ausentes, capas, letras, duplicatas por hash) -> Prévia com confiança -> Aplicar
Provedores (MusicBrainz/AcoustID) + fingerprint -> Reconhecimento de álbum -> Capas candidatas / classificação single/EP
Parser LRC -> Letras sincronizadas -> Busca de letras externas (opcional)
Tap de áudio no mixer -> Espectro e VU reais -> Visualizações extras
Fila de reprodução -> Now Playing / teclas de mídia (estado precisa ser fonte única)
Tema/skin próprio documentado -> Leitura .wsz (opcional, depois)
```

## Recomendação de MVP

Priorizar, nesta ordem:
1. Biblioteca persistente + modelo de dados + busca (base de tudo).
2. Fila, playlists, repetir/embaralhar, restaurar estado, teclas de mídia e Now Playing.
3. Espectro/VU reais, velocidade/balanço reais, presets de EQ persistentes, gapless.
4. Capas com regras de fallback, discografia por artista com Singles virtual, letras `.lrc`.
5. Library Fixer v1 100% offline: diagnóstico, prévia, confiança, backup e desfazer (tags ausentes/inconsistentes, capas externas vs embutidas, `.lrc` ao lado, duplicatas por hash). Um diferencial real sem rede.

Adiar:
- Fingerprint e provedores online: dependem do pipeline seguro e de decisão de licença (Chromaprint) e privacidade.
- Dedup semântico single↔álbum na fila: depende de IDs e fingerprint.
- Skins `.wsz`, visualizações avançadas, rename/organização: valor menor ou risco maior.
- Testes automatizados e notarização: transversais, mas começar os testes do pipeline de escrita junto com o item 5.

## Concorrentes (resumo para decisões)

| App | Aprendizado |
|---|---|
| MusicBrainz Picard | Padrão de identificação; interface densa, escreve direto, sem desfazer amigável |
| OneTagger | Rápido, em lote, automático; poucos controles de segurança |
| foobar2000 | Extensível, gapless, ReplayGain, OpenLyrics; UI pouco acolhedora |
| Cog / Audacious | Leves, muitos formatos; poucos recursos de biblioteca |
| Swinsian | Biblioteca forte, detecção de duplicatas, edição de tags; sem estética retrô |
| Doppler / Vox | Foco em UX e áudio de alta qualidade; Vox com Now Playing e formatos lossless |

## Fontes

- Briefing do projeto e PROJECT.md (HIGH para requisitos e restrições).
- Conhecimento de domínio sobre os apps listados (MEDIUM; sem verificação online nesta rodada).
- A validar: licenças de Chromaprint/AcoustID, termos de uso e limites do MusicBrainz e Cover Art Archive, formato `.eqf`, suporte de `MPRemoteCommandCenter` em app sem Xcode (LOW).
