#ifndef WINEUP_ID3_H
#define WINEUP_ID3_H

#ifdef __cplusplus
extern "C" {
#endif

/// Versão maior do ID3v2 (3 ou 4) em MP3/WAV; 0 se não há ID3v2; -1 em erro.
int wid3_tag_version(const char *path);

/// 1 se o arquivo MP3 tem ID3v1, 0 se não, -1 em erro.
int wid3_has_id3v1(const char *path);

/// Grava campos de tag em MP3/WAV preservando a versão ID3 original, frames desconhecidos
/// e sem criar ID3v1. NULL (texto) ou 0 (faixa/disco) = não mexer. Retorna 0 em sucesso.
/// Sem ID3v2 prévio: MP3 recebe v2.3 e WAV recebe v2.4 (o INFO do WAV nunca é tocado).
/// Capa (cover != NULL e coverLen > 0): remove todas as APIC e grava uma capa frontal.
int wid3_write(const char *path, const char *title, const char *artist, const char *album,
               const char *albumArtist, const char *genre, const char *year,
               int track, int disc, const char *composer, const char *comment,
               const unsigned char *cover, long coverLen, const char *coverMime);

#ifdef __cplusplus
}
#endif

#endif
