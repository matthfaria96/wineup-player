# Avisos de terceiros — Wineup Player

O Wineup usa as bibliotecas abaixo. Cada uma mantém sua licença original.

| Componente | Licença | Observação |
|---|---|---|
| SFBAudioEngine (Stephen F. Booth) | MIT | Motor de reprodução, tags e ReplayGain |
| dumb (módulos tracker) | permissiva (DUMB) | via SFBAudioEngine |
| Monkey's Audio (MAC) | BSD-3-Clause | via SFBAudioEngine |
| TagLib | LGPL-2.1 / MPL-1.1 | via SFBAudioEngine, embutido como biblioteca |
| WavPack | BSD-3-Clause | framework dinâmico |
| libogg, libvorbis, libFLAC, libopus, libspeex | BSD-3-Clause (Xiph) | frameworks dinâmicos |
| libsndfile, mpg123, LAME, Musepack, libtta-cpp | LGPL | **frameworks dinâmicos substituíveis** em `Contents/Frameworks`; o código-fonte de cada um está nos repositórios de sbooth/*-binary-xcframework e nos projetos originais |

Texto completo das licenças: https://github.com/sbooth/SFBAudioEngine/tree/main/LICENSES

## Adicionados na Fase 2

| Componente | Licença | Observação |
|---|---|---|
| GRDB.swift (Gwendal Roué) | MIT | Banco SQLite da biblioteca (migrations, FTS5) |
| TagLib (CXXTagLib) | LGPL-2.1 / MPL-1.1 | Escrita de tags ID3; linkado estaticamente sob MPL-1.1. Fonte: https://taglib.org |

## Clipes de vídeo embutidos (painel visual, categorias de vídeo)

Trechos de 10–20 s, sem som, reduzidos a 960 px. Cada um mantém a licença original.

| Arquivo | Obra | Autor | Licença | Fonte |
|---|---|---|---|---|
| animacao/animacao-namakura.mp4 | Namakura Gatana (1917) | Jun'ichi Kōuchi | Domínio público | https://commons.wikimedia.org/wiki/File:Namakura_Gatana_with_music.webm |
| cinema/cinema-hooligan.mp4 | Happy Hooligan: A Trip to the Moon (1917) | International Film Service | Domínio público | https://commons.wikimedia.org/wiki/File:Happy_Hooligan_-_A_Trip_To_The_Moon-1917.webm |
| natureza/natureza-aurora.mp4 | May 2024 aurora timelapse near Calgary | ver página da fonte | CC BY 3.0 | https://commons.wikimedia.org/wiki/File:May_2024_aurora_timelapse_near_Calgary.webm |
| natureza/natureza-floresta.mp4 | Lost Forest Research Natural Area | BLM Oregon & Washington | Domínio público (obra do governo dos EUA) | https://commons.wikimedia.org/wiki/File:Lost_Forest_Research_Natural_Area_(44359678475).webm |
| natureza/natureza-praia.mp4 | Fujitsuka-hama Beach in Summer, Japan – Aerial Video | ver página da fonte | CC BY 3.0 | https://commons.wikimedia.org/wiki/File:Fujitsuka-hama_Beach_in_Summer,_Japan_-_Aerial_Video.webm |
| universo/universo-buracos-negros.mp4 | New Simulation Sheds Light on Spiraling Supermassive Black Holes | NASA Goddard | Domínio público (NASA) | https://images.nasa.gov/details/GSFC_20181002_SMBH_m13043_Simulation |
| universo/universo-colisao.mp4 | Galaxy Collision Animation – James Webb Space Telescope Science | NASA/ESA/STScI (via Commons) | CC BY 3.0 | https://commons.wikimedia.org/wiki/File:Galaxy_Collision_Animation-_James_Webb_Space_Telescope_Science.webm |

Os clipes CC BY exigem crédito ao autor: os nomes completos estão nas páginas de origem.

## Skin embutido "Noite Estrelada"

| Item | Autor | Licença | Fonte |
|---|---|---|---|
| A Noite Estrelada (1889), pintura | Vincent van Gogh | Domínio público | https://commons.wikimedia.org/wiki/File:Van_Gogh_-_Starry_Night_-_Google_Art_Project.jpg |
| Cormorant Garamond (fonte) | Christian Thalmann | SIL Open Font License 1.1 (texto em Skins/noite-estrelada/OFL-Cormorant.txt) | https://github.com/google/fonts/tree/main/ofl/cormorantgaramond |
| Caveat Brush (fonte) | Pablo Impallari | SIL Open Font License 1.1 (texto em Skins/noite-estrelada/OFL-CaveatBrush.txt) | https://github.com/google/fonts/tree/main/ofl/caveatbrush |

Moldura, botões e puxador foram desenhados pelo Wineup a partir da pintura.

## Skin embutido "Neon Gótico"

| Item | Autor | Licença | Fonte |
|---|---|---|---|
| Press Start 2P (fonte pixel) | CodeMan38 | SIL Open Font License 1.1 (texto em Skins/neon-gotico/OFL-PressStart2P.txt) | https://github.com/google/fonts/tree/main/ofl/pressstart2p |

Personagem chibi, raio, caveiras, corações, fundos, moldura e botões são arte original do Wineup (vetorial, gerada por código). A ilustração artwork.jpg foi feita pelo autor do Wineup.

<!-- versoes:inicio -->
## Versões exatas (geradas do Package.resolved a cada build)

| Pacote | Versão | Origem |
|---|---|---|
| avfaudioextensions | 0.5.1 | https://github.com/sbooth/AVFAudioExtensions |
| cdumb | 2.0.3 | https://github.com/sbooth/CDUMB |
| cspeex | 1.2.1 | https://github.com/sbooth/CSpeex |
| cxxaudioringbuffer | 0.2.0 | https://github.com/sbooth/CXXAudioRingBuffer |
| cxxdispatchsemaphore | 0.4.1 | https://github.com/sbooth/CXXDispatchSemaphore |
| cxxmessagequeue | 0.2.2 | https://github.com/sbooth/CXXMessageQueue |
| cxxmonkeysaudio | 12.13.0 | https://github.com/sbooth/CXXMonkeysAudio |
| cxxqueue | 0.1.1 | https://github.com/sbooth/CXXQueue |
| cxxtaglib | 2.3.2 | https://github.com/sbooth/CXXTagLib |
| cxxunfairlock | 0.3.1 | https://github.com/sbooth/CXXUnfairLock |
| flac-binary-xcframework | 0.2.0 | https://github.com/sbooth/flac-binary-xcframework |
| grdb.swift | 7.11.1 | https://github.com/groue/GRDB.swift |
| lame-binary-xcframework | 0.1.2 | https://github.com/sbooth/lame-binary-xcframework |
| mpc-binary-xcframework | 0.1.2 | https://github.com/sbooth/mpc-binary-xcframework |
| mpg123-binary-xcframework | 0.3.1 | https://github.com/sbooth/mpg123-binary-xcframework |
| ogg-binary-xcframework | 0.1.3 | https://github.com/sbooth/ogg-binary-xcframework |
| opus-binary-xcframework | 0.3.0 | https://github.com/sbooth/opus-binary-xcframework |
| sfbaudioengine | 0.14.0 | https://github.com/sbooth/SFBAudioEngine |
| sndfile-binary-xcframework | 0.1.2 | https://github.com/sbooth/sndfile-binary-xcframework |
| tta-cpp-binary-xcframework | 0.1.2 | https://github.com/sbooth/tta-cpp-binary-xcframework |
| vorbis-binary-xcframework | 0.1.2 | https://github.com/sbooth/vorbis-binary-xcframework |
| wavpack-binary-xcframework | 0.2.0 | https://github.com/sbooth/wavpack-binary-xcframework |
<!-- versoes:fim -->
