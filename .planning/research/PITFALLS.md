# Armadilhas do Domínio

**Domínio:** player de música nativo para macOS com Library Fixer (gravação de tags)
**Pesquisado em:** 2026-10-19
**Confiança geral:** MEDIA. Baseado no código atual (`AudioEngineService.swift`, `build-app.sh`, `PROJECT.md`) e em conhecimento de domínio. A web não foi consultada nesta passada. Itens marcados [VERIFICAR] precisam de confirmação nos docs oficiais ou em teste antes de virar decisão.

## Armadilhas críticas

Causam reescrita, perda de dados do usuário ou bloqueio de distribuição.

### 1. Gravar tags in-place sem backup nem verificação (viola o Core Value)
**O que dá errado:** o TagLib/SFBAudioEngine reescreve o arquivo no lugar. Falta de energia, disco cheio, volume externo desmontado ou bug no meio da escrita deixa um arquivo truncado. Reescrever uma faixa de 40 MB para trocar uma tag também apaga o padding original, e a capa embutida pode ser recodificada.
**Por que acontece:** o caminho feliz funciona em teste, e o "desfazer" é pensado como um recurso de UI e não como um mecanismo de dados.
**Consequências:** perda de arquivos do usuário, que é o oposto do Core Value.
**Prevenção:**
- Fluxo transacional: copiar o original para um diretório de backup (mesmo volume, para usar clone APFS via `clonefile`, que é instantâneo e quase não gasta espaço). Gravar na cópia de trabalho, reabrir e verificar (tags esperadas e duração iguais, decodificação dos primeiros e últimos segundos, hash do trecho de áudio igual ao original), e só então trocar atomicamente com `replaceItemAt`.
- Diário de operações (tabela `tag_edits` com valores antigos e novos, hash antes e depois, caminho do backup). O "desfazer" restaura do diário, sem depender da memória da sessão.
- Política de retenção de backups, visível ao usuário (espaço usado, limpeza manual).
- Modo "somente prévia" como padrão. Gravação em lote exige confirmação.
**Detecção:** qualquer caminho de código que chame `writeMetadata` sem passar pelo orquestrador transacional. Testes com arquivo somente leitura, disco cheio simulado e kill no meio da escrita.
**Fase:** modelo de dados e Library Fixer. A infraestrutura de backup/diário deve existir antes da primeira gravação.

### 2. Corromper ou degradar tags por particularidades de formato
**O que dá errado:**
- **ID3v2:** misturar v2.3 e v2.4 (o Apple Music e vários players antigos leem mal UTF-8 e `TDRC` em v2.4; versão 2.3 usa `TYER`/`TDAT`). Regravar um 2.4 como 2.3 perde frames. Frames desconhecidos (`PRIV`, `GEOB`, `TXXX` de outros softwares) são descartados por reescritas ingênuas. ID3v1 e APE duplicados criam conflito. Unsynchronisation e tag no fim do arquivo também são fontes de erro.
- **MP4/M4A:** átomos `ilst` (`©nam`, `covr`, `trkn` como inteiros e não texto, `----` para campos livres). Se o `moov` está depois do `mdat` e a tag cresce, o arquivo precisa ser reescrito inteiro. Perder `covr` tipo JPEG ou PNG, ou mudar o tipo, quebra a exibição.
- **Vorbis comments (FLAC/Ogg/Opus):** nomes de campo são livres (ARTIST vs ALBUMARTIST, DATE vs YEAR, múltiplos valores repetidos). Imagem é um bloco `METADATA_BLOCK_PICTURE` (FLAC) ou base64 (Ogg). Mexer em FLAC sem padding reescreve o arquivo inteiro.
- **Capa embutida:** imagens de 5 a 10 MB fazem tags gigantes, o que desacelera a leitura e pode estourar o limite de 16 MB de bloco do FLAC. Existe também o risco de recomprimir JPEG sem aviso.
- **Encoding:** Latin-1 mal interpretado (mojibake) em tags antigas ao "corrigir" títulos. Normalização Unicode (NFC vs NFD) mudando nomes sem intenção.
**Prevenção:**
- Matriz de testes por formato com arquivos reais pequenos (fixtures de ID3v2.3, v2.4, MP4 com moov no fim, FLAC com e sem padding, Opus, com capa grande). Teste de ida e volta que compara todos os campos e frames desconhecidos antes e depois.
- Política explícita: preservar a versão do ID3 de cada arquivo, preservar frames desconhecidos, nunca recomprimir capa sem consentimento, limitar tamanho de capa embutida (ex.: avisar acima de 1 a 2 MB, redimensionar só com opção do usuário).
- Usar a mesma biblioteca de escrita para tudo e não misturar duas bibliotecas editando o mesmo arquivo.
- Campos que o app não conhece não entram no diff do Fixer; só os que o usuário aprovou.
**Detecção:** testes de ida e volta falhando; diff de bytes do trecho de áudio (deve ser idêntico); arquivos que mudaram de tamanho muito mais do que o esperado.
**Fase:** Library Fixer (gravação). Corpus de fixtures deve ser montado na fase de testes automatizados, antes.

### 3. Tocar no grafo do AVAudioEngine fora do trecho permitido (já ocorreu uma vez)
**O que dá errado:** o SFBAudioEngine aborta se o grafo for alterado fora de `sourceNode → mainMixerNode`. Medidores, espectro, balanço e velocidade tendem a empurrar o desenvolvedor para inserir nós novos (`AVAudioUnitVarispeed`/`TimePitch`, mixer separado para pan) depois do mixer ou conectar o mixer a outro destino.
**Prevenção:**
- Tudo que processa áudio entra na cadeia entre `sourceNode` e `mainMixerNode`, dentro de `modifyProcessingGraph`, e é religado no `reconfigureProcessingGraph` (hoje só o EQ é religado; uma cadeia EQ → varispeed → pan precisa ser reconstruída inteira ali, na ordem correta).
- Velocidade: `AVAudioUnitTimePitch` (preserva tom) ou `AVAudioUnitVarispeed` (muda tom, comportamento Winamp). Decidir e documentar. Atenção: tempo percorrido e `currentTime` do SFB não consideram a taxa; o relógio da UI e as letras `.lrc` vão dessincronizar se não forem corrigidos pelo fator de taxa. [VERIFICAR]
- Balanço: `mainMixerNode.pan` ou `AVAudioMixerNode` dedicado no trecho permitido; testar com áudio mono.
- Teste de fumaça automatizado: tocar uma faixa 44,1 kHz, depois 96 kHz e depois mono, com cada efeito ligado, sem abortar.
**Detecção:** `abort()`/assert ao trocar de faixa com formato diferente; áudio mudo depois de troca de faixa; cadeia que só funciona na primeira faixa.
**Fase:** áudio real (VU, velocidade, balanço). Escrever a camada "cadeia de efeitos ordenada" uma vez e reutilizar.

### 4. Medidor e espectro com custo ou bloqueio na thread de áudio
**O que dá errado:** `installTap` entrega buffers em thread interna e o callback é chamado de forma assíncrona; alocar memória, usar locks, `@Published`/`ObservableObject`, `DispatchQueue.main.sync` ou Swift arrays que crescem dentro dele causa glitches e cliques. FFT feita no callback com `vDSP` recriando `FFTSetup` a cada chamada é outro erro comum. Taps com tamanho de buffer enorme (ex.: 4096 a 8192 frames) aumentam a latência visual; buffer pequeno demais aumenta a carga.
**Prevenção:**
- No tap: copiar o mínimo (ou calcular RMS/pico) para um buffer circular preallocado e sem lock (atômicos), e ler esse buffer em um timer da UI (display link, 30 a 60 Hz). FFT (`vDSP_DFT`/`vDSP_fft_zrip` com setup criado uma vez, janela Hann precalculada) fora da thread de áudio.
- Suavização (decaimento de pico, escala logarítmica em dB e bandas por oitava) na camada de apresentação, não no tap.
- Instalar o tap no mixer principal ou no nó de EQ, uma única vez, e reinstalar quando o grafo for reconfigurado (taps podem ser perdidos na reconfiguração) [VERIFICAR com o SFBAudioEngine 0.14.0: se instalar tap no `mainMixerNode` conta como "modificar o grafo"].
- Pausar a análise quando a janela do espectro está oculta ou o app está em segundo plano (economia de CPU e bateria).
- Sem alocação no tap: verificar com Instruments (Time Profiler e Allocations), que existe nas Command Line Tools? Não necessariamente; ver armadilha 14.
**Detecção:** cliques ao abrir o painel de espectro; CPU alta com música tocando; UI travando ao arrastar a janela; medidor com atraso perceptível ao ouvido (deve ficar abaixo de ~50 ms).
**Fase:** áudio real (VU e espectro).

### 5. Gapless, troca de taxa de amostragem e formato
**O que dá errado:** o gapless real depende de enfileirar a próxima faixa com o mesmo formato (ou reconfigurar o grafo no ponto exato). Faixas com taxas diferentes (44,1 kHz e 96 kHz), canais diferentes ou DSD fazem o SFBAudioEngine disparar `reconfigureProcessingGraph`; se o app religar errado, a faixa seguinte fica muda ou o EQ some. Atraso do encoder (MP3 e AAC) cria silêncio no início e no fim se o decoder não aplicar `iTunSMPB`/LAME header. O "fim da faixa" via `audioPlayerEndOfAudio` + `play(nextURL)` na main thread cria um buraco audível (isso não é gapless).
**Prevenção:**
- Usar a fila nativa do `AudioPlayer` (`enqueue`) para a próxima faixa em vez de chamar `play` ao receber `EndOfAudio`. Pré-carregar a próxima faixa alguns segundos antes do fim.
- Teste de gapless com material conhecido (ex.: faixas de um álbum ao vivo ou de DJ mix) e comparação auditiva e por análise de amostras.
- Dispositivo de saída: o hardware pode mudar de taxa; o `AVAudioEngine` reage ao evento `AVAudioEngineConfigurationChange` (troca de fones, AirPods, HDMI). Tratar a notificação e reiniciar o engine preservando posição e estado.
- Um mixer final com taxa fixa da saída evita reconstruir a cadeia de efeitos a cada troca (o conversor da Apple faz a reamostragem), mas é preciso testar que o SFB permite isso [VERIFICAR].
**Detecção:** silêncio entre faixas de álbum contínuo; faixa sem som após álbum com taxas mistas; app mudo depois de conectar AirPods.
**Fase:** reprodução avançada (fila, repetir, embaralhar) e robustez de saída de áudio.

### 6. Sandbox, bookmarks e acesso a pastas de música
**O que dá errado:** o app hoje roda sem sandbox (assinatura ad-hoc). Se mais tarde for à Mac App Store, ou se a distribuição fora dela adotar o sandbox, todo o código de acesso a arquivos precisa ser refeito. Guardar só `URL.path` no SQLite deixa o app sem acesso depois de reiniciar. Security-scoped bookmarks quebram quando a pasta é movida ou o volume muda de UUID, e `startAccessingSecurityScopedResource` sem o `stop` correspondente vaza recursos do kernel (limite de ~256 por processo).
**Prevenção:**
- Decisão explícita agora: distribuição fora da App Store com Developer ID, hardened runtime e **sem sandbox**, ou sandbox desde o início. Recomendação: sem sandbox no início (menor atrito para bibliotecas grandes e para gravar tags) e abstrair o acesso a arquivos atrás de um protocolo (`LibraryRoot` com bookmark opcional), para não espalhar `URL` cru pelo código. Registrar a decisão em Key Decisions.
- Se sandbox: entitlements `files.user-selected.read-write` e `files.bookmarks.app-scope`, bookmark por **raiz** da biblioteca (não por arquivo), resolver com `.withSecurityScope`, tratar `isStale` regravando o bookmark, e manter uma contagem de acessos ativos por raiz.
- Volumes externos: identificar a raiz por bookmark e por UUID do volume, marcar itens como "offline" em vez de apagar do banco quando o disco não está montado.
- Arquivos abertos via "Abrir com" ou arrastar têm acesso temporário; não persistir esses caminhos como biblioteca sem pedir uma raiz.
**Detecção:** biblioteca "vazia" depois de reiniciar; erros de permissão só em disco externo; arquivos sumindo do índice ao desmontar o HD.
**Fase:** biblioteca persistente (decidir antes de desenhar o esquema de caminhos).

### 7. Varredura de 100 mil arquivos que trava, repete ou apaga dados
**O que dá errado:** ler tags de 100 mil arquivos na thread errada; abrir cada arquivo com decoder completo só para ler a duração; reler tudo a cada abertura; atualizar a UI a cada arquivo; seguir symlinks em ciclo; tratar renomeação como remoção mais inserção (perde playlists, contagem de plays e correções do Fixer).
**Prevenção:**
- Varredura em duas etapas: (1) enumeração rápida com `FileManager.enumerator(at:includingPropertiesForKeys:)` pedindo `contentModificationDate`, `fileSize`, `fileResourceIdentifier` e `.isSymbolicLinkKey`; (2) leitura de tags só dos arquivos novos ou alterados (comparar mtime e tamanho). Paralelismo limitado (ex.: número de núcleos, via `TaskGroup` com limite) e I/O em lotes de transação (ex.: 500 a 2000 linhas por commit).
- Identidade do arquivo pelo `fileResourceIdentifier`/inode e volume mais caminho, para detectar renomeações e movimentos sem perder metadados. Remoção só depois de uma segunda varredura confirmar (ou marcar como "ausente").
- Capas extraídas para cache em disco com miniaturas (nunca guardar blob de 3 MB por faixa na tabela principal). Deduplicar capa por hash.
- Progresso para a UI com coalescência (a cada ~100 ms), cancelamento e retomada. Prioridade `.utility`.
- Teste de carga com biblioteca sintética de 100 mil arquivos (arquivos mínimos gerados por script) com meta de tempo e de memória.
**Detecção:** primeira varredura leva mais de alguns minutos; segunda varredura quase tão lenta quanto a primeira; memória crescendo; playlists que perdem faixas depois que o usuário reorganiza pastas.
**Fase:** biblioteca persistente.

### 8. SQLite: concorrência, migrações e esquema
**O que dá errado:** uma única conexão compartilhada entre threads (corrupção ou `SQLITE_MISUSE`); `database is locked` entre o scanner (escritor) e a UI (leitora); sem WAL; migração manual sem versão; transação por linha (100 mil `INSERT` leva horas); normalização insuficiente que mistura arquivo, gravação e lançamento (o requisito já pede esse modelo); FTS5 sem manter a tabela de índice sincronizada.
**Prevenção:**
- Usar GRDB.swift (MIT; suporta SwiftPM, `DatabasePool` com WAL, leitores concorrentes e um escritor serializado, `DatabaseMigrator`, FTS5) em vez de SQLite cru ou Core Data [VERIFICAR versão atual e compatibilidade com Swift 5.9 e Command Line Tools]. Um único escritor.
- `PRAGMA journal_mode=WAL`, `foreign_keys=ON`, `busy_timeout`, migrações numeradas desde a primeira versão, banco em `Application Support`.
- Modelo desde o começo: `file` (caminho, volume, id, mtime, hash opcional), `recording`, `release`, `artist`, `artwork`, `lyrics`, e tabelas ligando-os. Correções do Fixer em tabela separada (valor lido vs valor corrigido) para o "desfazer" e para não reescrever sempre o arquivo.
- Backup do banco antes de cada migração; banco é reconstruível por nova varredura, mas playlists e correções não são, então exportá-las em formato texto (JSON/M3U8) periodicamente.
- Busca: FTS5 com tokenizer `unicode61 remove_diacritics` (buscar "Beyonce" encontra "Beyoncé"); prefix index.
**Detecção:** `SQLITE_BUSY` em log; UI congela durante varredura; consultas de listagem lentas com 100 mil linhas (faltam índices por artista/álbum).
**Fase:** biblioteca persistente (esquema e migrações são decisões de fase 1 dessa trilha).

### 9. Distribuição: LGPL, assinatura e notarização com frameworks embutidos
**O que dá errado:**
- **LGPL:** embutir lame, mpg123, mpc, sndfile, tta como `.framework` dinâmicos é o caminho correto, mas é preciso: incluir o texto da licença, avisos de copyright, oferta ou cópia do código-fonte correspondente **na versão exata** usada, e permitir que o usuário substitua a biblioteca (relink/replace). A assinatura com Developer ID e hardened runtime torna a substituição pelo usuário mais difícil: um framework trocado perde a assinatura e a *library validation* recusa carregá-lo. Também há risco de o `libsndfile`/`mpg123` trazerem dependências com licença diferente (ex.: libsndfile é LGPL-2.1, mas FLAC/Ogg/Opus/Vorbis que ele usa são BSD). Documentar tudo em `THIRD_PARTY_NOTICES.md`. Se o SFBAudioEngine for linkado estaticamente ao binário, o MIT dele convive com as LGPL dinâmicas, mas confirmar que os frameworks LGPL não ficam estaticamente ligados dentro do executável.
- **Notarização:** hardened runtime (`codesign --options runtime`), assinatura **de dentro para fora** (primeiro os frameworks e dylibs aninhados, depois o app) com certificado Developer ID e *timestamp* seguro (`--timestamp`). `--force --sign -` em loop (como no `build-app.sh` atual) é só ad-hoc e não passa na notarização. Não usar `--deep` como solução permanente. Fluxo: `notarytool submit --wait`, `stapler staple`, `spctl --assess`. O script atual copia `*.framework` do `.build`, mas frameworks do SwiftPM às vezes ficam como dylib/XCFramework em locais diferentes e com `@rpath` incorreto; verificar com `otool -L` e `otool -l` que não há caminhos absolutos do `.build`.
- **Entitlements:** library validation pode precisar de `com.apple.security.cs.disable-library-validation` se os frameworks LGPL forem assinados por outra identidade; a alternativa preferível é assinar todos com o mesmo Team ID.
- **Sem Xcode completo:** `notarytool`, `stapler` e `codesign` fazem parte das Command Line Tools (confirmar com `xcrun --find notarytool`). Conta paga do Apple Developer Program é necessária e é um bloqueio que não é técnico.
**Prevenção:** script `scripts/release.sh` separado do `build-app.sh` de desenvolvimento; checklist de conformidade LGPL (versões, links para o fonte, como substituir) incluída no pacote e no site; validação final em um Mac limpo (outra conta de usuário, ou a VM tart do projeto Sirena) baixando o `.dmg` pela internet (atributo de quarentena), não copiando por rede local.
**Detecção:** Gatekeeper diz "app danificado" ou "desenvolvedor não identificado"; `spctl -a -vv` rejeita; crash ao iniciar com "code signature invalid" ou "library not loaded".
**Fase:** distribuição (última), mas o desenho do empacotamento (Frameworks, rpath, mesmo Team ID) deve ser validado cedo com um build de teste assinado.

### 10. APIs externas: MusicBrainz, AcoustID, capas e letras
**O que dá errado:**
- **MusicBrainz:** limite de aproximadamente 1 requisição por segundo por IP; exige `User-Agent` identificando o app e contato (genérico ou ausente leva a bloqueio). Estourar o limite resulta em HTTP 503. Dados do MusicBrainz são CC0 (núcleo) e CC BY-NC-SA (alguns dados suplementares); uso comercial de serviço pago exige plano comercial [VERIFICAR termos atuais].
- **AcoustID:** exige chave de API por aplicação (gratuita para uso não comercial; comercial exige acordo) e o fingerprint vem do Chromaprint (`fpcalc`, LGPL 2.1 ou MIT conforme o componente; verificar a licença da build). Enviar fingerprints é um envio de dados do usuário, o que exige aviso de privacidade (já há na restrição). Guardar a chave no binário distribuído a expõe (é aceitável para AcoustID, mas não para chaves pagas).
- **Cover Art Archive:** boa fonte de capas, com capas de qualidade e licenças variadas; hospedada no archive.org com redirecionamentos (tratar 307).
- **Letras:** provedores (Genius, Musixmatch, LyricFind) têm termos que **proíbem armazenar/redistribuir** o texto das letras sem licença; scraping de sites de letras viola os termos e é risco jurídico. A letra é obra protegida. LRCLIB é um serviço aberto de letras sincronizadas, mas com origem colaborativa, sem garantia de direito autoral [VERIFICAR termos].
**Prevenção:**
- Cliente HTTP único com fila, limitador de taxa (token bucket) por host, cache persistente das respostas (por MBID ou fingerprint), `User-Agent: WineupPlayer/x.y (contato)`, retentativa com *backoff* exponencial respeitando `Retry-After`. Lote do Fixer processa na velocidade do limite e mostra a estimativa de tempo ao usuário (100 mil faixas a 1/s são mais de 27 horas; o Fixer precisa ser incremental e interrompível, e priorizar o que o usuário selecionou).
- Privacidade: modo offline como padrão; tela de consentimento listando o que é enviado (fingerprint e duração, ou texto das tags) e para quem.
- Letras: priorizar `.lrc`/letras embutidas **do próprio usuário** (já é o requisito); busca online só como opção, sem redistribuir nem exportar o texto, com a fonte e os termos citados. Não incluir letras em backups compartilhados nem no repositório.
- Resultados do MusicBrainz têm vários lançamentos para a mesma gravação (edições, remasters, compilações); escolher o lançamento errado é a causa mais comum de "correção" que piora a tag. A confiança do Fixer deve considerar duração, número de faixas, ano e o contexto da pasta (álbum vizinho), nunca o primeiro resultado.
**Detecção:** HTTP 503/429; correções com ano ou álbum de compilação; muitos arquivos do mesmo álbum atribuídos a lançamentos diferentes.
**Fase:** Library Fixer / provedores. A pesquisa de termos deve ser refeita na fase (os termos mudam).

### 11. "Correção" automática que piora a biblioteca
**O que dá errado:** o Fixer trata diferença como erro: troca "feat." por "ft.", capitaliza títulos em outros idiomas, remove "(Remastered)", une artistas diferentes com o mesmo nome, ou separa artistas com "&" quando o nome oficial contém "&" (Simon & Garfunkel). Mescla de duplicatas apaga a versão de maior qualidade (FLAC vs MP3 de mesma faixa). Detecção de duplicatas só por nome, ou só por hash do arquivo (tags diferentes dão hashes diferentes).
**Prevenção:** estilo de nomenclatura configurável e **desligado por padrão** nas regras estéticas; separar "erro objetivo" (campo vazio, mojibake, ano inválido, capa ausente) de "preferência"; duplicatas por impressão acústica + duração + tags, e o app nunca apaga nada, só marca e propõe (mover para a Lixeira com `trashItem`, reversível); confiança por campo e não por faixa; lote exige aprovação em amostra antes de aplicar o resto.
**Detecção:** taxa de rejeição alta na prévia; reclamações de nomes de artistas "unidos" ou "partidos".
**Fase:** Library Fixer.

## Armadilhas moderadas

### 12. Skins `.wsz`: formato, bitmaps e direitos autorais
**O que dá errado:** `.wsz` é um ZIP com BMPs (e alguns PNGs) de nomes e tamanhos fixos (`main.bmp` 275x116, `cbuttons.bmp`, `titlebar.bmp`, `eqmain.bmp`, `pledit.txt`, `region.txt`, etc.). Problemas típicos: BMPs de 8 bits com paleta, 24 bits, formatos RLE e BMPs com cabeçalho inválido que `NSImage` recusa ou renderiza com cores trocadas; nomes de arquivo com maiúsculas e minúsculas variadas e com subpastas; arquivos ausentes (a skin deve herdar da skin padrão); `region.txt` para janelas não retangulares; `viscolor.txt` (cores do espectro); fonte de bitmap `text.bmp`/`numbers.bmp`; posições em pixels em escala 1x que ficam borradas em Retina se escaladas por interpolação (usar *nearest neighbor*). Skins "modernas" (Winamp 3/5, `.wal`) são outro formato (XML) e não são compatíveis; a UI atual (SwiftUI com painéis AMP) tem layout próprio, então mapear sprites exige uma camada de renderização por coordenadas.
**Direitos autorais:** cada skin é obra do autor; **não incluir skins do arquivo da internet no app nem no repositório**. Skins padrão do Winamp (base skin) são da Nullsoft/WCL, então não copiar a skin base nem os sprites do repositório do Winamp (a WCL proíbe). Permitir que o usuário carregue arquivos locais é seguro; distribuir não é.
**Segurança:** ZIP malicioso (zip-slip com `../`, zip bomb) – extrair para um diretório temporário, validar o caminho de cada entrada, limitar tamanho total e descompactar apenas os arquivos esperados.
**Prevenção:** formato próprio documentado primeiro (como já planejado); `.wsz` como importador opcional depois, com um corpus de teste de poucas skins que o próprio projeto cria ou que têm licença livre; decodificação de BMP própria ou via `CGImageSource`, testada com paleta de 8 bits; fallback por sprite.
**Fase:** skins (adiar até o núcleo estar estável).

### 13. Persistência de estado e Now Playing
**O que dá errado:** `MPNowPlayingInfoCenter` e `MPRemoteCommandCenter` exigem atualizar `elapsedPlaybackTime` e `playbackRate` (com velocidade ≠ 1 as teclas de mídia e a barra do sistema mostram posição errada); sem registrar os comandos, as teclas de mídia abrem o Apple Music; o app pode perder o *focus* de mídia para outro player. Restaurar estado exige guardar a posição, a fila e o item atual por identificador (não por índice), e tratar arquivos que desapareceram.
**Prevenção:** módulo único de "sessão de mídia" que reflete o estado do player; testar teclas físicas de mídia e Controle de Centro; restaurar a fila por IDs do banco.
**Fase:** controles do sistema.

### 14. Construir e testar sem Xcode completo
**O que dá errado:** `XCTest` e o novo `swift-testing` normalmente vêm com o Xcode; só com Command Line Tools `swift test` pode falhar com "no such module XCTest" ou não achar o *framework* de testes [VERIFICAR na máquina: `swift test` com CLT atual, e se o Swift Testing está incluído no toolchain das CLT]. Sem Xcode também não há Instruments (profilers de áudio e alocações), nem Xcode Cloud, nem UI testing (`XCUITest`). SwiftUI previews não funcionam. `xcodebuild` não existe. Alguns pacotes com `.xcframework` binário podem não resolver.
**Prevenção:**
- Primeira tarefa da fase de testes: rodar `swift test` com um teste trivial e registrar o resultado. Se falhar, opções: instalar o Swift toolchain de swift.org (inclui `swift-testing` e XCTest no toolchain), ou usar um executável de teste próprio (`swift run WineupSelfTests`) com *asserts* simples.
- Arquitetura: núcleo (biblioteca, Fixer, tags, banco) em um *target* de biblioteca separado e sem SwiftUI, para testar rápido; UI fina.
- Testes de áudio de ponta a ponta sem dispositivo de saída: `AVAudioEngine` em modo manual de renderização offline (`enableManualRenderingMode`) permite verificar o efeito real do EQ (a dívida "efeito audível do EQ não verificado"): gerar tom, aplicar ganho, medir RMS/FFT. Para a CI/VM, usar a VM tart.
- Para perfil sem Instruments: `os_signpost` e `sample <pid>` (CLT) para amostragem, `leaks`, `vmmap`.
**Fase:** a primeira, antes de qualquer outra (é infraestrutura bloqueante para o Core Value).

### 15. Efeito do EQ não verificado e problemas de ganho
**O que dá errado:** `AVAudioUnitEQ` com ganhos positivos soma e estoura 0 dBFS (clipping) sem *limiter*; `globalGain` limitado (-96 a +24 dB); o preamp deve compensar o maior ganho de banda. Mudar `bypass` em tempo real pode causar clique. Bandas paramétricas com `bandwidth = 1` oitava sobrepostas fazem um "ganho" soma além do esperado.
**Prevenção:** compensação automática do preamp (preamp = -max(ganho positivo)), teste de render offline por banda, *ramp* nos ganhos; ReplayGain aplicado no `volume` (ganho linear) com limite de pico para evitar clipping.
**Fase:** equalizador e ReplayGain.

### 16. Threading e concorrência do Swift
**O que dá errado:** o `AudioPlayer.Delegate` é chamado fora da main thread; o código atual faz `DispatchQueue.main.async` (correto), mas `var onEndOfAudio` e `currentTime` são lidos de várias threads sem isolamento (Swift 6 vai acusar). `try? player.setVolume` engole o erro. Mutação do estado de UI a partir do tap.
**Prevenção:** `@MainActor` para o estado de UI e um `actor` (ou fila serial) para o serviço de áudio; migrar para modo de concorrência estrita (`-strict-concurrency=complete`) cedo; tratar e registrar erros em vez de `try?` no caminho de áudio.
**Fase:** refatoração junto da fila e das playlists.

## Armadilhas menores

### 17. Nomes de arquivo, Unicode e tipos
`NFD` (HFS+) vs `NFC` nos caminhos: comparar caminhos sem normalizar duplica faixas. Extensões em maiúscula e UTI desconhecida (`.opus`, `.dsf`, `.wv`) fazem `public.audio` não abrir. `LSHandlerRank = Alternate` está certo (não roubar associação de arquivos do usuário).

### 18. Caminhos relativos e lista de reprodução
Playlists M3U/M3U8 com caminhos relativos mudam de significado quando o arquivo é movido; gravar com caminhos absolutos e relativos conforme o usuário escolher; ler M3U com encoding Latin-1 e UTF-8.

### 19. Letras `.lrc`
Carimbos `[mm:ss.xx]` com 2 ou 3 casas, múltiplos carimbos por linha, tags `[offset:]`, `[ar:]`; sincronização com velocidade de reprodução ≠ 1. Codificação não UTF-8 (GBK, Latin-1) em `.lrc` antigos.

### 20. Ícone, nome e identificadores
O `CFBundleIdentifier` `app.wineup.player` precisa de um domínio sob controle do projeto (ou mudar antes do primeiro lançamento): mudar depois quebra preferências, bookmarks e itens de chaveiro.

## Alertas por fase

| Fase / tema | Armadilha provável | Mitigação |
|-------------|--------------------|-----------|
| Infra de testes (primeira) | `swift test` indisponível só com CLT (14) | Verificar no primeiro dia; toolchain de swift.org ou runner próprio; render offline para áudio |
| Áudio real (VU, espectro, velocidade, balanço) | Abort do SFB (3), tap na thread de áudio (4), relógio com taxa ≠ 1 | Cadeia ordenada religada em `reconfigureProcessingGraph`; buffer circular sem lock |
| Reprodução avançada (fila, gapless) | Buraco entre faixas, saída muda (5) | `enqueue` do SFB, tratar `AVAudioEngineConfigurationChange` |
| Biblioteca persistente | Sandbox/bookmarks (6), varredura (7), SQLite (8) | Decidir sandbox antes do esquema; GRDB com WAL; identidade por inode; capas em cache |
| Modelo de dados | Misturar arquivo/gravação/lançamento | Esquema separado e correções em tabela própria |
| Controles do sistema | Now Playing com taxa errada (13) | Módulo único de sessão de mídia |
| Letras `.lrc` | Direitos de letras, formatos de carimbo (10, 19) | Só arquivos do usuário por padrão; busca online opcional |
| Library Fixer: diagnóstico e prévia | Correção que piora (11), lançamento errado (10) | Erro objetivo vs preferência; confiança por campo; nunca apagar |
| Library Fixer: gravação | Corrupção de arquivo (1, 2) | Backup por clone, verificação, troca atômica, diário, fixtures de formato |
| Provedores (MusicBrainz/AcoustID) | Rate limit, termos, privacidade (10) | Limitador, cache, User-Agent, consentimento, modo offline |
| EQ e ReplayGain | Clipping, EQ não verificado (15) | Preamp compensado, teste offline |
| Skins | Direitos de skins, ZIP malicioso, BMP (12) | Formato próprio primeiro; importador `.wsz` depois, validando ZIP |
| Distribuição | LGPL, assinatura de dentro para fora, notarização (9) | `release.sh` separado; mesmo Team ID; teste em Mac limpo com quarentena |

## Pontos que precisam de pesquisa dedicada na fase (flags)

- **Áudio real (tap + varispeed):** confirmar no código-fonte do SFBAudioEngine 0.14.0 (em `Wineup References`) o que é permitido em `modifyProcessingGraph` e o comportamento de taps.
- **Gravação de tags:** confirmar qual API de escrita do SFBAudioEngine/TagLib preserva frames ID3 desconhecidos e padding.
- **Distribuição:** pesquisar o fluxo de notarização com `notarytool` nas CLT e as exigências atuais da LGPL para frameworks assinados.
- **Provedores:** reler os termos atuais de MusicBrainz, AcoustID e do provedor de letras antes de implementar.
- **Testes:** verificar `swift test` nesta máquina.

## Fontes e confiança

| Tema | Fonte | Confiança |
|------|-------|-----------|
| Estado do código atual, restrição do grafo SFB, script de build | Arquivos do projeto lidos nesta pesquisa | ALTA |
| ID3/MP4/Vorbis, AVAudioEngine, sandbox/bookmarks, notarização, GRDB | Conhecimento de domínio (treinamento), não reverificado na web | MEDIA |
| Termos de MusicBrainz/AcoustID/letras, disponibilidade de `swift test` nas CLT | Conhecimento de domínio | BAIXA (verificar) |
