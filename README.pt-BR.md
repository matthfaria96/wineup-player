# Wineup Player

[English](README.md) · Português

Player de música nativo para macOS, feito para a sua biblioteca local e inspirado nos players clássicos do começo dos anos 2000: painéis independentes, equalizador de 10 bandas, medidor de nível com visor de tempo de 7 segmentos e skins para a janela inteira. Vem com um gerenciador de metadados que corrige tags, capas e letras com prévia e desfazer, então nenhum arquivo muda sem você ver antes.

Escrito em Swift e SwiftUI. App universal (Apple Silicon e Intel), macOS 14 Sonoma ou mais novo.

## Recursos

- **Dois jeitos de tocar**: a janela completa (biblioteca, player, FX, arte e letra lado a lado) ou a compacta, numa coluna só com player, equalizador e lista. Há ainda o layout "Padrão", sem a letra. Arraste um painel pelo título para reorganizar.
- **Skins para a janela inteira**: seis skins embutidos (Musical, Retro, PixelArt 16bit, Sci-Fi, Neon Gótico, Emoboy), com arte, fontes, molduras, botões e animação sutil próprios. Crie um skin a partir de qualquer imagem, ajuste cores e arte no editor e importe ou exporte arquivos `.wineupskin`. O visual simples "sem skin" também está incluído.
- **Biblioteca**: abre a sua pasta Música e navega por pasta, álbum, artista, estilo ou playlist; busca instantânea que ignora acentos; página do artista com Reproduzir tudo / Embaralhar; álbum virtual "Singles" para faixas soltas; tags de cor e playlists automáticas por cor. Nenhuma tag é regravada para montar essas visões.
- **Reprodução**: FLAC, MP3, AAC/M4A, ALAC, WAV, AIFF, Ogg Vorbis, Opus, Monkey's Audio, WavPack, Musepack, TTA e outros (via SFBAudioEngine), arquivos CUE, reprodução sem pausa entre faixas, importação e exportação de M3U/M3U8, fila com repetir e embaralhar, e a última sessão restaurada ao reabrir.
- **Som**: equalizador de 10 bandas com pré-amplificação, presets suaves e limitador de pico; ReplayGain; Correção de Som opcional (EBU R128, -14 LUFS) medida no próprio Mac; velocidade sem mudar o tom; balanço esquerda/direita; forma de onda real, espectro e medidor de nível.
- **Letras**: letras embutidas e arquivos `.lrc`, com destaque sincronizado, painel de letra grande e editor de sincronia com ajustes de ±0,25 s. A busca online opcional pode salvar um `.lrc` ao lado da música.
- **Gerenciador de metadados**: tabela dos seus arquivos com diagnóstico do que falta, busca de álbum no MusicBrainz, capas do Cover Art Archive e do iTunes, letras em lote, localizador de duplicadas, edição manual e histórico em que toda gravação pode ser desfeita. Cada gravação passa por backup e é conferida depois de salva.
- **Integração com o Mac**: teclas de mídia, Central de Controle e tela de bloqueio, atalhos clássicos (Z X C V B, espaço, setas), player pequeno na barra de menus, Ajustes (⌘,), dicas ao passar o mouse em todos os controles e 17 idiomas de interface.
- **Seu ecossistema é seu**: playlists, tags de cor, preferências de exibição e presets de EQ podem ser exportados para um arquivo e importados em outro Mac.

## Instalação

1. **Terminal, uma linha (recomendado):**

   ```sh
   curl -fsSL https://witchmymac.com/install.sh | bash -s wineup
   ```

   Baixa a versão mais recente do GitHub, confere o SHA-256, instala em Aplicativos e abre o app. Não aparece aviso do Gatekeeper, porque arquivos baixados pelo `curl` não ficam em quarentena. Rode de novo para atualizar.

2. **Baixe o DMG** em [Releases](https://github.com/matthfaria96/wineup-player/releases) ou em [witchmymac.com](https://witchmymac.com), abra e arraste o **Wineup Player** para Aplicativos. O app não é notarizado pela Apple, então libere uma vez no Terminal:

   ```sh
   xattr -dr com.apple.quarantine "/Applications/Wineup Player.app"
   ```

   Isso só remove do app a marca de "baixado da internet".

3. **Baixe o DMG** e libere pelos Ajustes do Sistema: abra o app, clique em **OK** no aviso e vá em **Ajustes do Sistema → Privacidade e Segurança → Abrir Mesmo Assim**.

## Privacidade e serviços online

O Wineup não tem telemetria e funciona offline. Consultas online só acontecem depois que você permite (pergunta uma vez; dá para mudar nas Opções do gerenciador de metadados). Com a permissão, o app envia título, artista, álbum e duração da música para:

- **MusicBrainz** e **Cover Art Archive** (tags e capas),
- **iTunes Search** (dicas de álbum e capas),
- **LRCLIB** e **NetEase Cloud Music** (letras); **Musixmatch** só se você informar o token da sua conta,
- **AcoustID**, só se você ligar e informar a sua chave e o `fpcalc`: vai uma impressão digital do som, nunca o áudio.

Os seus arquivos de áudio nunca saem do Mac.

## Compilar

Precisa do Xcode (para o build universal) ou das Command Line Tools.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/test.sh        # testes
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/build-app.sh   # build/Wineup Player.app
```

`UNIVERSAL=0` compila só para a arquitetura do Mac atual.

## Licença e créditos

O Wineup Player é software livre sob a [GNU General Public License v3.0](LICENSE).

Ele usa trabalhos de código aberto, cada um com a sua licença (lista completa em [Resources/THIRD_PARTY_NOTICES.md](Resources/THIRD_PARTY_NOTICES.md) e na janela Sobre do app):

- [SFBAudioEngine](https://github.com/sbooth/SFBAudioEngine), de Stephen F. Booth (MIT), com FLAC, Ogg, Vorbis, Opus, Speex, WavPack, Monkey's Audio (BSD) e libsndfile, mpg123, LAME, Musepack, TTA (LGPL, embutidos como frameworks dinâmicos substituíveis)
- [GRDB.swift](https://github.com/groue/GRDB.swift), de Gwendal Roué (MIT)
- [TagLib](https://taglib.org) (LGPL-2.1 / MPL-1.1)
- Skins: todos os skins embutidos e a arte deles são criação original de Matheus Faria, autor do Wineup; só as fontes vêm de terceiros
- Fontes dos skins sob a SIL Open Font License: VT323, Press Start 2P, Metal Mania, Orbitron
- Clipes de vídeo embutidos do Wikimedia Commons e da NASA (domínio público e CC BY 3.0)

O Wineup é um projeto independente inspirado nos players de música clássicos. Não tem vínculo nem aval do Winamp ou de qualquer outro player e não usa código, logotipos ou arte deles. Skins clássicos `.wsz` não são suportados; o Wineup tem formato de skin próprio.
