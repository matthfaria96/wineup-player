<!-- GSD:project-start source:PROJECT.md -->
## Project

**Wineup Player**

Player de música nativo para macOS (Swift + SwiftUI), inspirado na identidade e na experiência do Winamp clássico (1999–2005): painéis independentes (player, equalizador, playlist, busca, letras, capa), skins/temas e controle total do usuário sobre a biblioteca. O diferencial planejado é o **Wineup Library Fixer**, um assistente integrado que corrige tags, capas, letras e duplicatas com prévia, nível de confiança e opção de desfazer. Para quem tem coleção local de músicas, gosta da estética retrô e quer organizar tudo sem alternar entre vários aplicativos.

**Core Value:** Tocar a biblioteca local do usuário de forma confiável, com a interface clássica de painéis, e nunca danificar os arquivos dele.

### Constraints

- **Plataforma**: macOS 14+ (Swift 5.9 tools, SwiftUI) — SFBAudioEngine exige 11+, o app usa recursos do 14
- **Licenças**: dependências MIT/BSD/Apache preferidas; LGPL só como frameworks dinâmicos substituíveis, com avisos em `THIRD_PARTY_NOTICES.md`
- **Segurança dos arquivos**: nunca gravar tags, renomear ou mover sem prévia, confiança visível e backup — arquivos do usuário têm prioridade sobre automação
- **Privacidade**: sem telemetria; consultas externas (metadados, AcoustID) opcionais, informando o que é enviado, com modo offline
- **Ferramentas**: sem Xcode completo; qualquer dependência binária precisa resolver via SwiftPM com Command Line Tools
- **Escopo visual**: o visual clássico é um modo/skin; a biblioteca moderna não precisa parecer presa a 2001
<!-- GSD:project-end -->

<!-- release-notes-start (manual) -->
## Release e testes (manual)

- Versão e build: `VERSION`/`BUILD` no topo de `scripts/build-app.sh` + `WineupCore.version` (teste em SmokeTests). Atual: 1.1.0 (3).
- Build: `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/build-app.sh` (universal; `UNIVERSAL=0` nativo, `SKIP_TESTS=1`, `VERIFY_LAUNCH=0`). Mínimo macOS 14; o binário fica com SDK 14 de propósito: o tema Glass (`.glassEffect`, macOS 26+) funciona assim mesmo, e com o SDK 27 carimbado por vtool o SwiftUI não cria a janela ao abrir em segundo plano (`open -g`) e a janela perde 28 pt de altura.
- Ícone: `swift scripts/make-icon.swift Resources/wineup_player.png <saida.iconset>` + `iconutil -c icns` → `Resources/WineUp.icns` (corpo 824/1024, superelipse n=5).
- DMG: `~/Documents/witchmymac-release/make-dmg.sh "build/Wineup Player.app" WineupPlayer-<versão> ~/Documents/witchmymac-release/dist`.
- Temas internos (`Sources/Wineup/Theme/GlassTheme.swift`): `glass` (padrão, escuro, vidro/transparência), `none` (Sem skin escuro) e `none-light` (Sem skin claro); abaixo deles, os skins personalizados. Só o `none-light` é claro: cor fixa nova usa `theme.ink`/`theme.isLight` (não `Color.white`), e janelas novas usam `.wineupColorScheme()` em vez de `.preferredColorScheme(.dark)`; janelas de trabalho e suas subtelas (Metadados) usam `.themedWindow()` (fundo do tema, vidro, destaque) e superfícies `.themedSurface()`. Captura: `defaults write app.wineup.player.check themeID glass|none|none-light`.
- README em inglês (`README.md`) + `README.pt-BR.md`; instalação por `curl -fsSL https://witchmymac.com/install.sh | bash -s wineup`. Licença GPL-3.0; créditos em `Resources/THIRD_PARTY_NOTICES.md` (todo clipe, fonte ou arte embutida precisa de fonte e licença lá).
- Testes visuais sem atrapalhar o usuário: cópia do app com bundle id `app.wineup.player.check`, `open -g -n --env CFFIXED_USER_HOME=<pasta> --env WINEUP_MUTE=1`, biblioteca de demonstração via `wineup-demo <pasta>/Music` com o mesmo `CFFIXED_USER_HOME`, captura `screencapture -x -o -l <id>`. `WINEUP_OPEN_WINDOW=metadata|themes|about|videos` abre janelas. `WINEUP_METADATA_SHEET=album|cover|history|duplicates` abre uma subtela dos Metadados (álbum e capas pedem antes o consentimento online). Nunca rodar `scripts/ui-test.sh` (cliques reais) nem testar com o bundle id real.
<!-- release-notes-end -->

<!-- GSD:stack-start source:research/STACK.md -->
## Technology Stack

## Dependências SwiftPM (novas)
| Biblioteca | Versão | Licença | Uso | Confiança |
|---|---|---|---|---|
| GRDB.swift (groue) | 7.11.1 (`from: "7.11.1"`) | MIT | Biblioteca SQLite: migrations, FTS5, `ValueObservation` para a UI, DatabasePool (WAL) | ALTA (release e licença conferidas no GitHub) |
| ZIPFoundation (weichsel) | 0.9.20 | MIT | Ler `.wsz` (é ZIP) e pacotes de skin próprios, sem extrair para disco | ALTA |
| Chromaprint (acoustid) | 1.6.x (tag v1.6.2 vista no GitHub) | LGPL-2.1 efetivo (código próprio MIT + trechos FFmpeg) | Impressão acústica | MÉDIA (ver abaixo) |
### Por que GRDB e não SwiftData/Core Data/SQLite.swift
- SwiftData exige macros e o toolchain de Xcode para `@Model`; com só CLT é frágil. Core Data exige compilar `.xcdatamodeld` (momc, vem do Xcode). GRDB é SwiftPM puro e compila com `swift build`.
- GRDB dá FTS5 (busca instantânea na biblioteca), migrations versionadas e observação reativa. SQLite.swift é mais cru e sem observação.
- Modelo: tabelas `file`, `recording`, `release`, `artist`, `artwork`, `lyrics` (conforme PROJECT.md). Varredura incremental por `(path, size, mtime)` + inode/bookmark; hash de conteúdo só sob demanda.
### Chromaprint (fingerprint)
- Não há pacote SwiftPM confiável e mantido que eu tenha verificado (busca no GitHub sem resultado conclusivo). Recomendação: compilar `libchromaprint` como **dylib/framework dinâmico** embutido em `Contents/Frameworks` (mesmo mecanismo dos frameworks LGPL atuais no `build-app.sh`), usando **KissFFT** (permissivo) ou **vDSP/Accelerate** como FFT. NÃO usar a opção FFTW (GPL). Se compilar via CMake for inviável, alternativa: target C do SwiftPM com o fonte do chromaprint + KissFFT (código MIT próprio; o trecho FFmpeg LGPL exige ficar substituível, então preferir dylib).
- Fluxo: decodificar ~120 s com SFBAudioEngine (PCM) -> reamostrar 11025 Hz mono (AVAudioConverter) -> chromaprint -> POST AcoustID. Fingerprint é local; só o hash vai à rede.
- Validar em uma fase de spike (CMake está disponível? senão `brew`/build manual). Confiança MÉDIA.
## Frameworks da Apple (sem dependência externa)
| Necessidade | API | Observações |
|---|---|---|
| VU/pico | `installTap` no `mainMixerNode` (AVAudioEngine) ou, melhor, tap por render block | Tap de AVAudioEngine entrega buffers com latência e fora do thread de áudio; suficiente para VU a 30-60 fps. Calcular RMS/pico com `vDSP_rmsqv`/`vDSP_maxmgv`. ALTA |
| Espectro | `vDSP.FFT` / `vDSP_fft_zrip` (Accelerate), janela Hann (`vDSP_hann_window`), 1024-2048 pontos, bins logarítmicos, suavização com decaimento | Processar no tap, publicar com um ring buffer/atomic para a UI (`TimelineView`/`Canvas`). ALTA |
| Velocidade sem mudar tom | `AVAudioUnitTimePitch` (rate 0.25-4) | Inserir no mesmo trecho que o EQ. Alternativa `AVAudioUnitVarispeed` (muda o tom) para efeito "vinil". ALTA |
| Balanço | `AVAudioMixerNode.pan` / `AVAudioPlayerNode.pan` (-1..1) | Se o sourceNode da SFB não tiver pan, usar um `AVAudioMixerNode` extra antes do mainMixer. MÉDIA (verificar no grafo real) |
| ReplayGain | já na SFBAudioEngine (leitura de tags) + ganho no mixer | Não destrutivo |
| Controles de mídia | `MPNowPlayingInfoCenter`, `MPRemoteCommandCenter` (MediaPlayer.framework) | Em app sem NSApplication de Xcode funciona se o bundle for `.app`; exige definir `playbackState` e `MPMediaItemArtwork`. Teclas de mídia físicas passam por MPRemoteCommandCenter no macOS 14+. ALTA (API estável), testar no `.app` real |
| Atalhos | SwiftUI `.keyboardShortcut` e `Commands` | Atalhos globais: não necessário |
| Acesso a arquivos | Security-scoped bookmarks (`URL.bookmarkData`) | Só obrigatório se o app virar sandboxed; para distribuição direta (Developer ID) opcional, mas guardar bookmark ajuda a restaurar pastas |
| Rede (MusicBrainz, CAA, AcoustID) | `URLSession` + `Codable` + `async/await` | Sem Alamofire. Obrigatório: User-Agent identificando o app, limite de 1 req/s no MusicBrainz, cache local de respostas |
| Armazenar chave AcoustID | Keychain ou constante de app (a chave de aplicação é pública por natureza) | |
## Letras `.lrc`
- Escrever o parser próprio (~100 linhas): `[mm:ss.xx]`, múltiplas marcas por linha, tags `[ar:]`, `[ti:]`, `[offset:]`, e opcionalmente LRC enhanced `<mm:ss.xx>`. Não adicionar dependência: os pacotes Swift existentes são pequenos e pouco mantidos; o formato é trivial e testável. ALTA.
- Sincronização: busca binária pelo tempo de reprodução (`AVAudioEngine`/posição do SFB), `ScrollViewReader` para rolagem.
- Ler letra embutida (já funciona) e sidecar `.lrc` ao lado do arquivo.
## Library Fixer (escrita de tags)
- Usar a própria **SFBAudioEngine**: `SFBAudioFile` + `SFBAudioMetadata` + `writeMetadata(_:error:)` (confirmado no código do checkout: método `writeMetadata` em `SFBAudioFile.h` e implementações por formato). Cobre FLAC, MP3, M4A, Ogg, WAV, etc. via TagLib embutido, então **não adicionar TagLib separado**. ALTA para a existência da API; MÉDIA para cobertura por formato (testar cada formato com round-trip).
- Segurança: copiar o original para `~/Library/Application Support/Wineup/Backups/<hash>` antes de gravar; registrar a operação (antes/depois) em tabela `change_log` do GRDB para desfazer; gravar de forma atômica (tag em cópia temporária + `FileManager.replaceItemAt`). Verificar leitura pós-escrita e que o áudio decodificado (hash do PCM, ou ao menos duração e contagem de frames) não mudou.
## Metadados e capas
- MusicBrainz WS/2 (JSON) e Cover Art Archive: HTTP direto com `URLSession`; sem SDK. MusicBrainz exige User-Agent com contato e ~1 req/s; CAA entrega imagens por MBID de release/release-group (usar miniaturas 250/500 px). AcoustID: `lookup` com `fingerprint`+`duration`, chave de aplicação gratuita para uso não comercial; conferir termos antes de distribuir. MÉDIA (APIs estáveis há anos, termos para checar na fase).
- Cache de capas em disco (hash) e `NSCache` para miniaturas.
## Skins
- Formato próprio: pasta/`.wineupskin` (ZIP) com `skin.json` + PNGs @1x/@2x, decodificado por `Codable`; temas atuais viram skins embutidas.
- `.wsz` clássico: ZIP com BMPs (`main.bmp`, `cbuttons.bmp`, `numbers.bmp`, `pledit.txt`, `eqmain.bmp`, `region.txt`...). Leitura com ZIPFoundation + `NSImage`/`CGImageSource` (suporta BMP). Mapear sprites por coordenadas conhecidas do formato (documentado publicamente pela comunidade; reescrever, não copiar código do Winamp/WCL). Tratar como spike: escopo parcial (main, botões, números, EQ, playlist). MÉDIA.
- Referência de estudo permitida: WACUP Winamp-Modern-Skin (MIT) e vis_classic (MIT) para estrutura; nada da WCL.
## Testes
- **Swift Testing** (`import Testing`, `@Test`, `#expect`) está nos CLT neste ambiente (Testing.framework encontrado). `swift test` funciona só com CLT para Swift Testing. **XCTest NÃO vem completo nos CLT** em muitas instalações; não depender dele. Verificar com `swift test` no primeiro commit de testes. MÉDIA (confirmar execução real).
- Requisito de arquitetura: separar um target de biblioteca `WineupCore` (modelos, DB, scanner, LRC, fingerprint, tags) do executável `Wineup`, porque targets executáveis são difíceis de importar nos testes. Hoje o Package só tem `executableTarget`: refatorar.
- DB de teste: `DatabaseQueue()` em memória do GRDB. Áudio: gerar WAV/FLAC sintéticos pequenos (senoide) em fixtures; testar tap/FFT com senoide de frequência conhecida.
- UI/E2E: sem XCUITest (precisa Xcode). Usar testes de ViewModel; verificação visual manual.
## Assinatura e notarização (sem Xcode)
- `codesign --force --options runtime --timestamp --sign "Developer ID Application: ..."` (inside-out: cada dylib/framework em `Contents/Frameworks`, depois o `.app`), com `entitlements.plist` mínimo (hardened runtime; se algum framework binário não for assinado pelo mesmo Team ID, `com.apple.security.cs.disable-library-validation`).
- Notarizar com `xcrun notarytool submit app.zip --keychain-profile ... --wait` e `xcrun stapler staple`. `notarytool`/`stapler` fazem parte dos Command Line Tools (verificar com `xcrun --find notarytool`). Pré-requisito: conta Apple Developer paga (US$ 99/ano) e certificado Developer ID. Empacotar em `.dmg` com `hdiutil` (nativo). MÉDIA (depende do certificado do usuário).
- Atualização automática (Sparkle 2, MIT) é opcional e fica para depois; Sparkle é distribuído como binário SwiftPM e compatível com CLT, mas exige assinar o framework.
## O que NÃO usar
| Evitar | Motivo | Em vez disso |
|---|---|---|
| AudioKit | Segundo motor, redundante (já decidido) | AVAudioEngine + vDSP |
| SwiftData / Core Data | Precisa de ferramentas do Xcode (macros / momc) e é pior para FTS e varredura em lote | GRDB |
| TagLib direto | Já embutido via SFBAudioEngine; duplicaria LGPL | `SFBAudioFile.writeMetadata` |
| FFTW | GPL contamina o binário do Chromaprint | KissFFT ou vDSP |
| XCTest / XCUITest | Dependem do Xcode | Swift Testing |
| Plugins do Winamp (DLL), WCL, código Mixxx/Cog | Licença/inviável no macOS | Reescrever comportamento |
| Pacotes LRC/skin de terceiros pequenos | Mantenção incerta para ~100 linhas de código | Parser próprio |
| Alamofire e afins | Desnecessário | URLSession |
| `AVAudioPlayer`/`AVPlayer` para tocar | Perde decoders da SFB e o grafo do EQ | Continuar com SFB AudioPlayer |
## Instalação
## Notas de licença para THIRD_PARTY_NOTICES
## Lacunas / validar em spike
## Fontes
- GitHub releases: groue/GRDB.swift v7.11.1; weichsel/ZIPFoundation 0.9.20; sbooth/SFBAudioEngine 0.14.0; acoustid/chromaprint v1.6.2 e LICENSE.md (consultados em 2026-10-19).
- Código local: `.build/checkouts/SFBAudioEngine` (API `writeMetadata`).
- Ambiente local: `swift --version` (6.4), `Testing.framework` em CommandLineTools.
- APIs Apple (AVAudioEngine, Accelerate, MediaPlayer, notarytool): conhecimento de treinamento, não reverificado em docs nesta sessão (MÉDIA).
<!-- GSD:stack-end -->

<!-- GSD:conventions-start source:CONVENTIONS.md -->
## Conventions

Conventions not yet established. Will populate as patterns emerge during development.
<!-- GSD:conventions-end -->

<!-- GSD:architecture-start source:ARCHITECTURE.md -->
## Architecture

Architecture not yet mapped. Follow existing patterns found in the codebase.
<!-- GSD:architecture-end -->

<!-- GSD:skills-start source:skills/ -->
## Project Skills

No project skills found. Add skills to any of: `.claude/skills/`, `.agents/skills/`, `.cursor/skills/`, `.github/skills/`, or `.codex/skills/` with a `SKILL.md` index file.
<!-- GSD:skills-end -->

<!-- GSD:workflow-start source:GSD defaults -->
## GSD Workflow Enforcement

Before using Edit, Write, or other file-changing tools, start work through a GSD command so planning artifacts and execution context stay in sync.

Use these entry points:
- `/gsd-quick` for small fixes, doc updates, and ad-hoc tasks
- `/gsd-debug` for investigation and bug fixing
- `/gsd-execute-phase` for planned phase work

Do not make direct repo edits outside a GSD workflow unless the user explicitly asks to bypass it.
<!-- GSD:workflow-end -->



<!-- GSD:profile-start -->
## Developer Profile

> Profile not yet configured. Run `/gsd-profile-user` to generate your developer profile.
> This section is managed by `generate-claude-profile` -- do not edit manually.
<!-- GSD:profile-end -->
