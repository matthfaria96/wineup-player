#ifndef WINEUP_ID3_H
#define WINEUP_ID3_H

#ifdef __cplusplus
extern "C" {
#endif

/// Versão maior do ID3v2 (3 ou 4) em MP3/WAV; 0 se não há ID3v2; -1 em erro.
int wid3_tag_version(const char *path);

/// 1 se o arquivo MP3 tem ID3v1, 0 se não, -1 em erro.
int wid3_has_id3v1(const char *path);

#ifdef __cplusplus
}
#endif

#endif
