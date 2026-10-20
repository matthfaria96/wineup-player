#include "WineupID3.h"

#include <taglib/mpegfile.h>
#include <taglib/wavfile.h>
#include <taglib/id3v2tag.h>
#include <taglib/id3v2header.h>

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
