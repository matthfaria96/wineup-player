#include "WineupID3.h"

#include <taglib/mpegfile.h>
#include <taglib/wavfile.h>
#include <taglib/id3v2tag.h>
#include <taglib/id3v2header.h>
#include <taglib/id3v2frame.h>
#include <taglib/textidentificationframe.h>
#include <taglib/tstring.h>

#include <string>
#include <strings.h>

namespace {
enum class Kind { mp3, wav, other };

Kind kindOf(const char *path) {
    std::string p(path);
    auto dot = p.rfind('.');
    if (dot == std::string::npos) return Kind::other;
    const char *ext = p.c_str() + dot + 1;
    if (strcasecmp(ext, "mp3") == 0) return Kind::mp3;
    if (strcasecmp(ext, "wav") == 0 || strcasecmp(ext, "wave") == 0) return Kind::wav;
    return Kind::other;
}
}

extern "C" int wid3_tag_version(const char *path) {
    if (!path) return -1;
    try {
        switch (kindOf(path)) {
        case Kind::mp3: {
            TagLib::MPEG::File f(path, false);
            if (!f.isValid()) return -1;
            if (!f.hasID3v2Tag()) return 0;
            return (int)f.ID3v2Tag()->header()->majorVersion();
        }
        case Kind::wav: {
            TagLib::RIFF::WAV::File f(path, false);
            if (!f.isValid()) return -1;
            if (!f.hasID3v2Tag()) return 0;
            return (int)f.ID3v2Tag()->header()->majorVersion();
        }
        default:
            return -1;
        }
    } catch (...) {
        return -1;
    }
}

extern "C" int wid3_has_id3v1(const char *path) {
    if (!path) return -1;
    try {
        if (kindOf(path) != Kind::mp3) return -1;
        TagLib::MPEG::File f(path, false);
        if (!f.isValid()) return -1;
        return f.hasID3v1Tag() ? 1 : 0;
    } catch (...) {
        return -1;
    }
}

namespace {
using TagLib::String;

String utf8(const char *s) { return String(s, String::UTF8); }

void setText(TagLib::ID3v2::Tag *tag, const char *frameID, const String &text) {
    tag->removeFrames(frameID);
    auto *frame = new TagLib::ID3v2::TextIdentificationFrame(frameID, String::UTF8);
    frame->setText(text);
    tag->addFrame(frame);
}

// Número de faixa/disco: mantém o "/total" já existente.
void setNumber(TagLib::ID3v2::Tag *tag, const char *frameID, int value) {
    String suffix;
    auto existing = tag->frameList(frameID);
    if (!existing.isEmpty()) {
        String old = existing.front()->toString();
        int slash = old.find("/");
        if (slash >= 0) suffix = old.substr(slash);
    }
    setText(tag, frameID, String::number(value) + suffix);
}

void apply(TagLib::ID3v2::Tag *tag, const char *title, const char *artist, const char *album,
           const char *albumArtist, const char *genre, const char *year, int track, int disc) {
    if (title) tag->setTitle(utf8(title));
    if (artist) tag->setArtist(utf8(artist));
    if (album) tag->setAlbum(utf8(album));
    if (albumArtist) setText(tag, "TPE2", utf8(albumArtist));
    if (genre) setText(tag, "TCON", utf8(genre));
    // TagLib trabalha internamente com TDRC e rebaixa para TYER ao salvar em v2.3.
    // O texto vai cru (sem interpretar data), então "2019" continua "2019".
    if (year) setText(tag, "TDRC", utf8(year));
    if (track > 0) setNumber(tag, "TRCK", track);
    if (disc > 0) setNumber(tag, "TPOS", disc);
}
}

extern "C" int wid3_write(const char *path, const char *title, const char *artist, const char *album,
                          const char *albumArtist, const char *genre, const char *year,
                          int track, int disc) {
    if (!path) return -1;
    try {
        switch (kindOf(path)) {
        case Kind::mp3: {
            TagLib::MPEG::File f(path, true);
            if (!f.isValid()) return -2;
            bool had = f.hasID3v2Tag();
            int version = had ? (int)f.ID3v2Tag()->header()->majorVersion() : 3;
            apply(f.ID3v2Tag(true), title, artist, album, albumArtist, genre, year, track, disc);
            bool ok = f.save(TagLib::MPEG::File::ID3v2, TagLib::File::StripNone,
                             version == 3 ? TagLib::ID3v2::v3 : TagLib::ID3v2::v4,
                             TagLib::File::DoNotDuplicate);
            return ok ? 0 : -3;
        }
        case Kind::wav: {
            TagLib::RIFF::WAV::File f(path, true);
            if (!f.isValid()) return -2;
            bool had = f.hasID3v2Tag();
            int version = had ? (int)f.ID3v2Tag()->header()->majorVersion() : 4;
            apply(f.ID3v2Tag(), title, artist, album, albumArtist, genre, year, track, disc);
            // Só ID3v2: o chunk LIST/INFO existente fica intacto.
            bool ok = f.save(TagLib::RIFF::WAV::File::ID3v2, TagLib::File::StripNone,
                             version == 3 ? TagLib::ID3v2::v3 : TagLib::ID3v2::v4);
            return ok ? 0 : -3;
        }
        default:
            return -4;
        }
    } catch (...) {
        return -5;
    }
}
