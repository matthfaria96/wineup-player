# Wineup Player

English · [Português](README.pt-BR.md)

A native macOS music player for your local library, inspired by the classic desktop players of the early 2000s: independent panels, a 10-band equalizer, a level meter with a seven-segment time display, and full-window skins. It comes with a built-in metadata manager that fixes tags, covers and lyrics with a preview and undo, so your files are never changed without you seeing it first.

Written in Swift and SwiftUI. Universal app (Apple Silicon and Intel), macOS 14 Sonoma or later.

## Features

- **Two ways to play**: the full window (library, player, FX, artwork and lyrics side by side) or a compact single column with the player, equalizer and list. A third "Standard" layout drops the lyrics. Drag a panel by its title to rearrange the layout.
- **Skins for the whole window**: six built-in skins (Musical, Retro, PixelArt 16bit, Sci-Fi, Neon Gótico, Emoboy) with their own art, fonts, frames, buttons and subtle animation. Create a new skin from any image, edit colors and art in the skin editor, and import or export `.wineupskin` files. A plain "no skin" look is also included.
- **Library**: opens your Music folder and lets you browse by folder, album, artist, genre or playlist; instant accent-insensitive search; an artist page with Play all / Shuffle; a virtual "Singles" album for loose tracks; color tags and automatic playlists per color. Tags are never rewritten to build these views.
- **Playback**: FLAC, MP3, AAC/M4A, ALAC, WAV, AIFF, Ogg Vorbis, Opus, Monkey's Audio, WavPack, Musepack, TTA and more (via SFBAudioEngine), CUE sheets, gapless playback, M3U/M3U8 import and export, queue with repeat and shuffle, and the last session restored when you reopen the app.
- **Sound**: 10-band equalizer with preamp, gentle presets and a peak limiter; ReplayGain; optional loudness correction (EBU R128, -14 LUFS) measured on your Mac; speed control without pitch change; left/right balance; real waveform, spectrum and level meter.
- **Lyrics**: embedded lyrics and `.lrc` files, with synced highlighting, a large lyrics panel and a sync editor with ±0.25 s nudges. Optional online lookup can save a `.lrc` next to the song.
- **Metadata manager**: a table view of your files with a diagnosis of what is missing, album search on MusicBrainz, covers from the Cover Art Archive and iTunes, lyrics in batch, duplicate finder, manual editing, and a history where every save can be undone. Every write goes through a backup and is verified after saving.
- **Mac integration**: media keys, Control Center and Lock Screen now playing, classic keyboard shortcuts (Z X C V B, space, arrows), a small player in the menu bar, Settings (⌘,), hover hints that explain every control, and 17 interface languages.
- **Your setup is yours**: playlists, color tags, display preferences and EQ presets can be exported to a file and imported on another Mac.

## Install

1. **Terminal, one line (recommended):**

   ```sh
   curl -fsSL https://witchmymac.com/install.sh | bash -s wineup
   ```

   It downloads the latest release from GitHub, checks its SHA-256, installs it to Applications and opens it. There is no Gatekeeper prompt, because files downloaded with `curl` are not quarantined. Run it again to update.

2. **Download the DMG** from [Releases](https://github.com/matthfaria96/wineup-player/releases) or [witchmymac.com](https://witchmymac.com), open it and drag **Wineup Player** to Applications. The app is not notarized by Apple, so allow it once in Terminal:

   ```sh
   xattr -dr com.apple.quarantine "/Applications/Wineup Player.app"
   ```

   This only removes the "downloaded from the internet" mark from the app.

3. **Download the DMG** and allow it in System Settings instead: open the app, click **OK** on the warning, then go to **System Settings → Privacy & Security** and click **Open Anyway**.

## Privacy and online services

Wineup has no telemetry and works offline. Online lookups only happen after you allow them (asked once, changeable in the metadata manager's Options). When allowed, the app sends the title, artist, album and duration of a song to:

- **MusicBrainz** and the **Cover Art Archive** (tags and covers),
- **iTunes Search** (album hints and covers),
- **LRCLIB** and **NetEase Cloud Music** (lyrics); **Musixmatch** only if you enter your own account token,
- **AcoustID**, only if you turn it on and provide your own key and `fpcalc`: an acoustic fingerprint is sent, never the audio.

Your audio files never leave your Mac.

## Build from source

Requires Xcode (for the universal build) or the Command Line Tools.

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/test.sh        # tests
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/build-app.sh   # build/Wineup Player.app
```

`UNIVERSAL=0` builds only for the current Mac's architecture.

## License and credits

Wineup Player is free software under the [GNU General Public License v3.0](LICENSE).

It is built on open-source work, each under its own license (full list in [Resources/THIRD_PARTY_NOTICES.md](Resources/THIRD_PARTY_NOTICES.md) and in the app's About window):

- [SFBAudioEngine](https://github.com/sbooth/SFBAudioEngine) by Stephen F. Booth (MIT), with FLAC, Ogg, Vorbis, Opus, Speex, WavPack, Monkey's Audio (BSD) and libsndfile, mpg123, LAME, Musepack, TTA (LGPL, shipped as replaceable dynamic frameworks)
- [GRDB.swift](https://github.com/groue/GRDB.swift) by Gwendal Roué (MIT)
- [TagLib](https://taglib.org) (LGPL-2.1 / MPL-1.1)
- Skin fonts under the SIL Open Font License: VT323, Press Start 2P, Metal Mania, Orbitron
- Built-in video clips from Wikimedia Commons and NASA (public domain and CC BY 3.0)

Wineup is an independent project inspired by classic desktop music players. It is not affiliated with or endorsed by Winamp or any other player, and it uses none of their code, logos or artwork. Classic `.wsz` skins are not supported; Wineup has its own skin format.
