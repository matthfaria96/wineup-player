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
