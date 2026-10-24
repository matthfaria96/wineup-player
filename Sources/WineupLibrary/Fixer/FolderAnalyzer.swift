import Foundation
import SFBAudioEngine
import WineupID3

/// Lê todos os arquivos de áudio de uma pasta e aponta o que falta em cada um.
public enum FolderAnalyzer {
    /// Arquivos de áudio da pasta (subpastas inclusas), em ordem de caminho.
    public static func audioFiles(in folder: URL, recursive: Bool = true) -> [URL] {
        let keys: [URLResourceKey] = [.isRegularFileKey]
        let options: FileManager.DirectoryEnumerationOptions = recursive
            ? [.skipsHiddenFiles, .skipsPackageDescendants] : [.skipsHiddenFiles, .skipsSubdirectoryDescendants]
        guard let e = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys, options: options)
        else { return [] }
        var out: [URL] = []
        for case let url as URL in e where TagReader.audioExtensions.contains(url.pathExtension.lowercased()) {
            if (try? url.resourceValues(forKeys: Set(keys)).isRegularFile) == true { out.append(url) }
        }
        return out.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    /// Lê as tags de um arquivo (nunca grava).
    public static func read(_ url: URL) -> FixerFile {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize).map(Int64.init) ?? 0
        var file = FixerFile(url: url, size: size, isWritable: TagBackends.backend(for: url) != nil)
        if let audio = try? AudioFile(readingPropertiesAndMetadataFrom: url) {
            // Só o tamanho das capas importa aqui: sem o SHA-256 de cada imagem.
            let snap = TagSnapshot.read(file: audio, hashPictures: false)
            file.tech = tech(audio, url: url)
            file.fields = snap.fields
            file.pictureCount = snap.pictures.count
            file.coverBytes = snap.pictures.first?.byteCount ?? 0
            file.duration = snap.duration
            file.hasEmbeddedLyrics = !(snap.fields["lyrics"] ?? "").isEmpty
        }
        file.hasSidecarLyrics = FileManager.default.fileExists(atPath: file.lyricsURL.path)
        let text = file.hasSidecarLyrics ? try? String(contentsOf: file.lyricsURL, encoding: .utf8) : file.fields["lyrics"]
        if let text, !text.isEmpty { file.lyricsSynced = LyricsInfo(text).isSynced }
        file.issues = issues(of: file)
        return file
    }

    static func tech(_ audio: AudioFile, url: URL) -> AudioTech {
        let p = audio.properties
        var t = AudioTech()
        t.codec = p.formatName ?? url.pathExtension.uppercased()
        t.bitrate = p.bitrate.map { Int($0.rounded()) }
        t.sampleRate = p.sampleRate
        t.channels = p.channelCount.map { Int($0) }
        t.bitDepth = p.bitDepth.flatMap { $0 > 0 ? Int($0) : nil }
        t.tagFormat = tagFormat(url)
        return t
    }

    /// Como o Mp3tag mostra na coluna "Etiqueta": ID3v2.3, ID3v2.4 (+ID3v1), FLAC, MP4, Vorbis…
    static func tagFormat(_ url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "mp3":
            let v = url.path.withCString { wid3_tag_version($0) }
            let v1 = url.path.withCString { wid3_has_id3v1($0) } == 1
            let main = v > 0 ? "ID3v2.\(v)" : (v1 ? "" : "sem tag")
            return [main, v1 ? "ID3v1" : ""].filter { !$0.isEmpty }.joined(separator: " + ")
        case "wav", "wave":
            let v = url.path.withCString { wid3_tag_version($0) }
            return v > 0 ? "RIFF + ID3v2.\(v)" : "RIFF INFO"
        case "flac": return "FLAC (Vorbis)"
        case "ogg", "oga", "opus": return "Vorbis Comment"
        case "m4a", "mp4", "aac", "alac": return "MP4"
        case "aif", "aiff": return "AIFF (ID3)"
        case "ape", "wv", "mpc": return "APEv2"
        default: return url.pathExtension.uppercased()
        }
    }

    /// Bytes da capa embutida (frontal, senão a primeira), para mostrar na tela.
    public static func embeddedCover(_ url: URL) -> Data? {
        guard let file = try? AudioFile(readingPropertiesAndMetadataFrom: url) else { return nil }
        let pics = file.metadata.attachedPictures
        return (pics.first { $0.type == .frontCover } ?? pics.first)?.imageData
    }

    /// Leituras simultâneas no máximo: o TagLib bloqueia a thread, e uma tarefa por arquivo esgota o pool.
    public static let maxConcurrentReads = 6

    public static func analyze(_ urls: [URL], concurrency: Int = maxConcurrentReads) async -> [FixerFile] {
        let width = max(1, concurrency)
        let files = await withTaskGroup(of: (Int, FixerFile).self) { group in
            var out = [FixerFile?](repeating: nil, count: urls.count)
            var next = 0
            // Começa com `width` leituras e põe a próxima a cada uma que termina.
            while next < min(width, urls.count) {
                let (i, url) = (next, urls[next])
                group.addTask { (i, read(url)) }
                next += 1
            }
            for await (i, f) in group {
                out[i] = f
                if next < urls.count {
                    let (j, url) = (next, urls[next])
                    group.addTask { (j, read(url)) }
                    next += 1
                }
            }
            return out.compactMap { $0 }
        }
        return markDuplicates(files)
    }

    public static func issues(of f: FixerFile) -> Set<FixerIssue> {
        var out: Set<FixerIssue> = []
        if f.value("title").isEmpty { out.insert(.missingTitle) }
        if f.value("artist").isEmpty { out.insert(.missingArtist) }
        if f.value("album").isEmpty { out.insert(.missingAlbum) }
        if f.value("year").isEmpty { out.insert(.missingYear) }
        if f.value("trackNumber").isEmpty { out.insert(.missingTrack) }
        if f.value("genre").isEmpty { out.insert(.missingGenre) }
        if !f.hasCover { out.insert(.missingCover) }
        if !f.hasLyrics { out.insert(.missingLyrics) }
        if f.duplicateGroup != nil { out.insert(.duplicate) }
        return out
    }

    /// Mesma música (artista + título normalizados, ou nome do arquivo) com duração até 3 s de diferença.
    public static func markDuplicates(_ files: [FixerFile]) -> [FixerFile] {
        var buckets: [String: [Int]] = [:]
        for (i, f) in files.enumerated() {
            let title = f.value("title").isEmpty ? FilenameGuess.parse(f.url).title : f.value("title")
            let key = TextMatch.normalize(f.value("artist")) + "|" + TextMatch.normalize(title)
            guard key != "|" else { continue }
            buckets[key, default: []].append(i)
        }
        var result = files.map { f -> FixerFile in
            var c = f; c.duplicateGroup = nil; c.issues.remove(.duplicate); return c
        }
        var group = 0
        for indices in buckets.values.sorted(by: { $0[0] < $1[0] }) where indices.count > 1 {
            var used = Set<Int>()
            for i in indices where !used.contains(i) {
                let twins = indices.filter { j in
                    j != i && !used.contains(j) && closeDurations(files[i].duration, files[j].duration)
                }
                guard !twins.isEmpty else { continue }
                group += 1
                for k in [i] + twins {
                    used.insert(k)
                    result[k].duplicateGroup = group
                    result[k].issues.insert(.duplicate)
                }
            }
        }
        return result
    }

    private static func closeDurations(_ a: Double?, _ b: Double?) -> Bool {
        guard let a, let b else { return true }
        return abs(a - b) <= 3
    }
}
