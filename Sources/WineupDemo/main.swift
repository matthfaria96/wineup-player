import AppKit
import AVFoundation
import Foundation
import SFBAudioEngine
import WineupLibrary

// wineup-demo [pasta] · wineup-demo --showcase <pasta> (vitrine para as capturas do site)
// Gera faixas sintetizadas com tags e capas, varre a biblioteca do app e cria playlists e tags de cor.

struct DemoTrack {
    let title: String
    let artist: String
    let album: String?
    let genre: String?
    let number: Int
    let year: String
    let seconds: Double
    let root: Double      // nota base (Hz)
    let tempo: Double     // BPM
    let format: String    // "flac" ou "m4a"
    let lyrics: [String]?
}

let catalog: [DemoTrack] = [
    .init(title: "Abertura do Vinho", artist: "Os Taninos", album: "Noites de Vinho", genre: "Rock", number: 1, year: "2024", seconds: 34, root: 220, tempo: 112, format: "flac",
          lyrics: ["Abre a garrafa devagar", "A noite começa a tocar", "Taninos no ar", "E o som vai te levar"]),
    .init(title: "Safra Antiga", artist: "Os Taninos", album: "Noites de Vinho", genre: "Rock", number: 2, year: "2024", seconds: 30, root: 196, tempo: 96, format: "flac", lyrics: nil),
    .init(title: "Rolha Solta", artist: "Os Taninos", album: "Noites de Vinho", genre: "Rock", number: 3, year: "2024", seconds: 28, root: 247, tempo: 128, format: "flac", lyrics: nil),
    .init(title: "Decantar", artist: "Os Taninos", album: "Noites de Vinho", genre: "Rock", number: 4, year: "2024", seconds: 32, root: 174.6, tempo: 88, format: "m4a", lyrics: nil),
    .init(title: "Última Taça", artist: "Os Taninos", album: "Noites de Vinho", genre: "Rock", number: 5, year: "2024", seconds: 36, root: 207.7, tempo: 100, format: "m4a",
          lyrics: ["Última taça da noite", "O disco gira sem fim", "Guardo o som do teu riso", "Tocando dentro de mim"]),
    .init(title: "Ondas Curtas", artist: "Maré Sintética", album: "Frequências", genre: "Eletrônica", number: 1, year: "2023", seconds: 30, root: 261.6, tempo: 124, format: "m4a", lyrics: nil),
    .init(title: "Estática Azul", artist: "Maré Sintética", album: "Frequências", genre: "Eletrônica", number: 2, year: "2023", seconds: 30, root: 293.7, tempo: 120, format: "flac", lyrics: nil),
    .init(title: "Sinal Fraco", artist: "Maré Sintética", album: "Frequências", genre: "Eletrônica", number: 3, year: "2023", seconds: 26, root: 329.6, tempo: 132, format: "flac", lyrics: nil),
    .init(title: "Fim de Transmissão", artist: "Maré Sintética", album: "Frequências", genre: "Eletrônica", number: 4, year: "2023", seconds: 34, root: 246.9, tempo: 110, format: "m4a", lyrics: nil),
    // Singles: sem álbum ou álbum de uma faixa só.
    .init(title: "Café às Três", artist: "Lia Sol", album: nil, genre: "Pop", number: 1, year: "2025", seconds: 28, root: 349.2, tempo: 104, format: "m4a",
          lyrics: ["Café às três da manhã", "A cidade dorme em paz", "Uma canção no rádio", "E nada mais"]),
    .init(title: "Ladeira", artist: "Bento Grave", album: "Ladeira (Single)", genre: "MPB", number: 1, year: "2025", seconds: 30, root: 233.1, tempo: 92, format: "flac", lyrics: nil),
    .init(title: "Demo Sem Nome", artist: "Desconhecido do Porão", album: nil, genre: nil, number: 1, year: "2022", seconds: 24, root: 277.2, tempo: 116, format: "flac", lyrics: nil),
]

let sampleRate = 44_100.0

/// Melodia simples: arpejo em escala menor com harmônicos, baixo e bumbo; estéreo com leve panorâmica.
func synthesize(_ t: DemoTrack, seed: Int) -> AVAudioPCMBuffer {
    let frames = AVAudioFrameCount(t.seconds * sampleRate)
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 2)!
    let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames)!
    buffer.frameLength = frames
    let left = buffer.floatChannelData![0], right = buffer.floatChannelData![1]
    let scale: [Double] = [0, 3, 5, 7, 10, 12, 7, 5]          // menor pentatônica + oitava
    let beat = 60.0 / t.tempo
    let step = beat / 2
    for i in 0..<Int(frames) {
        let time = Double(i) / sampleRate
        let stepIndex = Int(time / step)
        let degree = scale[(stepIndex * (seed % 3 + 1) + stepIndex / 8) % scale.count]
        let freq = t.root * pow(2, degree / 12)
        let local = time.truncatingRemainder(dividingBy: step)
        let env = exp(-local * 6) * min(local * 80, 1)
        let lead = (sin(2 * .pi * freq * time) + 0.35 * sin(4 * .pi * freq * time) + 0.15 * sin(6 * .pi * freq * time)) * env
        let bassFreq = t.root / 2 * pow(2, (stepIndex / 8 % 2 == 0 ? 0 : 5) / 12.0)
        let bass = sin(2 * .pi * bassFreq * time) * 0.5
        let kickLocal = time.truncatingRemainder(dividingBy: beat)
        let kick = sin(2 * .pi * (55 + 90 * exp(-kickLocal * 30)) * kickLocal) * exp(-kickLocal * 9)
        let fade = min(time / 1.5, 1) * min((t.seconds - time) / 2, 1)
        let pan = 0.5 + 0.35 * sin(time * 0.6 + Double(seed))
        let mono = (0.38 * lead + 0.28 * bass + 0.55 * kick) * fade
        left[i] = Float(mono * (1 - pan) * 1.25)
        right[i] = Float(mono * pan * 1.25)
    }
    return buffer
}

/// Capa quadrada 600×600 com degradê e iniciais.
func cover(title: String, hue: CGFloat) -> Data {
    let size = 600
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let rect = NSRect(x: 0, y: 0, width: size, height: size)
    NSGradient(colors: [NSColor(hue: hue, saturation: 0.75, brightness: 0.55, alpha: 1),
                        NSColor(hue: (hue + 0.12).truncatingRemainder(dividingBy: 1), saturation: 0.85, brightness: 0.18, alpha: 1)])!
        .draw(in: rect, angle: -60)
    for k in 0..<5 {
        let r = CGFloat(120 + k * 70)
        NSColor.white.withAlphaComponent(0.05).setStroke()
        let ring = NSBezierPath(ovalIn: NSRect(x: 380 - r / 2, y: 120 - r / 2, width: r, height: r))
        ring.lineWidth = 6
        ring.stroke()
    }
    let style = NSMutableParagraphStyle()
    style.alignment = .left
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.systemFont(ofSize: 54, weight: .heavy),
        .foregroundColor: NSColor.white,
        .paragraphStyle: style,
    ]
    NSString(string: title.uppercased()).draw(in: NSRect(x: 44, y: 60, width: 520, height: 260), withAttributes: attrs)
    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

func write(_ t: DemoTrack, index: Int, to dir: URL) throws -> URL {
    let base = String(format: "%02d %@ - %@", t.number, t.artist, t.title).replacingOccurrences(of: "/", with: "-")
    let folder = dir.appendingPathComponent(t.album ?? "Singles", isDirectory: true)
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    let wav = folder.appendingPathComponent(base + ".wav")
    let out = folder.appendingPathComponent(base + "." + t.format)
    try? FileManager.default.removeItem(at: out)
    let buffer = synthesize(t, seed: index)
    if t.format == "m4a" {
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: sampleRate,
                                       AVNumberOfChannelsKey: 2, AVEncoderBitRateKey: 192_000]
        let file = try AVAudioFile(forWriting: out, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
        try file.write(from: buffer)
    } else {
        // WAV 16 bits + afconvert (o conversor da SFB deixou o STREAMINFO do FLAC sem total de amostras).
        let settings: [String: Any] = [AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: sampleRate,
                                       AVNumberOfChannelsKey: 2, AVLinearPCMBitDepthKey: 16,
                                       AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false]
        do {
            let file = try AVAudioFile(forWriting: wav, settings: settings, commonFormat: .pcmFormatFloat32, interleaved: false)
            try file.write(from: buffer)
        }
        let convert = Process()
        convert.executableURL = URL(fileURLWithPath: "/usr/bin/afconvert")
        convert.arguments = ["-f", "flac", "-d", "flac", wav.path, out.path]
        try convert.run()
        convert.waitUntilExit()
        try? FileManager.default.removeItem(at: wav)
        guard convert.terminationStatus == 0 else { throw CocoaError(.fileWriteUnknown) }
    }
    let audio = try AudioFile(readingPropertiesAndMetadataFrom: out)
    let meta = audio.metadata
    meta.title = t.title
    meta.artist = t.artist
    meta.albumTitle = t.album
    meta.albumArtist = t.album == nil ? nil : t.artist
    meta.genre = t.genre
    meta.releaseDate = t.year
    meta.trackNumber = t.album == nil ? nil : t.number
    meta.lyrics = t.lyrics?.joined(separator: "\n")
    let hue = CGFloat((t.album ?? t.title).unicodeScalars.reduce(0) { $0 + Int($1.value) } % 100) / 100
    let art = showcaseCover(for: t) ?? cover(title: t.album ?? t.title, hue: hue)
    meta.attachPicture(AttachedPicture(imageData: art, type: .frontCover))
    try audio.writeMetadata()
    try writeShowcaseLyrics(for: t, audio: out)
    return out
}

// MARK: Execução

// Medição de varredura: wineup-demo --scanbench N
// Cria uma faixa FLAC real (tags + capa), copia N vezes num diretório temporário e mede a
// primeira varredura completa num banco temporário (arquivos lidos por segundo).
if CommandLine.arguments.count == 3, CommandLine.arguments[1] == "--scanbench", let count = Int(CommandLine.arguments[2]) {
    let base = FileManager.default.temporaryDirectory.appendingPathComponent("wineup-scanbench-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: base) }
    let source = DemoTrack(title: "Amostra", artist: "Banda", album: "Disco", genre: "Rock", number: 1, year: "2025",
                           seconds: 3, root: 220, tempo: 120, format: "flac", lyrics: ["linha"])
    let sample = try write(source, index: 0, to: base.appendingPathComponent("origem"))
    let lib = base.appendingPathComponent("lib")
    for i in 0..<count {
        let dir = lib.appendingPathComponent("Artista \(i % 50)/Album \(i % 400)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: sample, to: dir.appendingPathComponent("\(i).flac"))
    }
    let db = try LibraryDatabase(path: base.appendingPathComponent("bench.sqlite").path)
    let root = try LibraryRootStore(db: db).addRoot(lib)
    let started = Date()
    let result = try await WineupLibrary.Scanner(database: db).scan(rootID: root.id) { _ in }
    let seconds = Date().timeIntervalSince(started)
    print(String(format: "varredura: %d arquivos em %.2f s (%.0f arquivos/s)", result.read, seconds, Double(result.read) / seconds))
    exit(0)
}

// Modo sintético (medições): wineup-demo --synthetic N <banco.sqlite> <pastaRaiz>
// Insere N faixas direto no banco, sem criar arquivos de áudio.
if CommandLine.arguments.count == 5, CommandLine.arguments[1] == "--synthetic", let count = Int(CommandLine.arguments[2]) {
    let db = try LibraryDatabase(path: CommandLine.arguments[3])
    // Mesma forma de caminho que o app usa ao abrir a pasta (/private/tmp vira /tmp).
    let root = URL(fileURLWithPath: CommandLine.arguments[4]).standardizedFileURL.path
    let genres = ["Rock", "Pop", "Jazz", "Blues", "Folk", "Metal", "Soul", "Funk", "Reggae", "Samba"]
    let rootID: Int64 = try await db.pool.write { d in
        try d.execute(sql: "INSERT INTO library_root(uuid,path,online,added_at) VALUES (?,?,1,?)",
                      arguments: [UUID().uuidString, root, Date()])
        return d.lastInsertedRowID
    }
    var start = 0
    while start < count {
        let end = min(start + 1000, count)
        try await db.pool.write { d in
            for i in start..<end {
                try d.execute(sql: """
                    INSERT INTO audio_file(root_id,path,inode,size,mtime_ns,status,duration)
                    VALUES (?,?,?,?,?,'present',?)
                    """, arguments: [rootID, "\(root)/Artista \(i % 400)/Album \(i % 2500)/\(i).flac", i, 1000, 1, 200.0])
                let fid = d.lastInsertedRowID
                let tags = ScannedTags(title: "Faixa \(i)", artist: "Artista \(i % 400)",
                                       album: i % 9 == 0 ? nil : "Album \(i % 2500)",
                                       genre: i % 13 == 0 ? nil : genres[i % genres.count],
                                       trackNumber: i % 12 + 1, discNumber: 1, duration: 200)
                try CatalogWriter.ingest(d, audioFileID: fid, tags: tags, fallbackTitle: "\(i)")
            }
        }
        start = end
    }
    // Playlist grande (até 10 mil faixas) e algumas tags de cor, para medir a abertura de playlists.
    let collections = CollectionsStore(database: db)
    let big = try collections.createPlaylist(named: "Playlist Grande")
    let listed = (0..<min(count, 10_000)).map { "\(root)/Artista \($0 % 400)/Album \($0 % 2500)/\($0).flac" }
    let added = try collections.append(paths: listed, toPlaylist: big.id)
    let colors = ["green", "blue", "purple", "red", "orange", "yellow"]
    for i in stride(from: 0, to: min(count, 3000), by: 7) {
        _ = try collections.setMark(path: "\(root)/Artista \(i % 400)/Album \(i % 2500)/\(i).flac", color: colors[i % colors.count])
    }
    print("sintético: \(count) faixas em \(root); playlist com \(added) faixas")
    exit(0)
}

// Arquivos reais (medições): wineup-demo --fixtures N <pasta>
// Cria uma faixa FLAC curta e copia N vezes com tags variadas (algumas incompletas e repetidas).
if CommandLine.arguments.count == 4, CommandLine.arguments[1] == "--fixtures", let count = Int(CommandLine.arguments[2]) {
    let target = URL(fileURLWithPath: CommandLine.arguments[3], isDirectory: true)
    let source = DemoTrack(title: "Amostra", artist: "Banda", album: "Disco", genre: "Rock", number: 1, year: "2025",
                           seconds: 1, root: 220, tempo: 120, format: "flac", lyrics: nil)
    let sample = try write(source, index: 0, to: target.appendingPathComponent(".origem"))
    let genres = ["Rock", "Pop", "Jazz", "Blues", "Folk", "Metal", "Soul", "Funk", "Reggae", "Samba"]
    for i in 0..<count {
        let artist = "Artista \(i % 120)", album = "Album \(i % 600)"
        let dir = target.appendingPathComponent("\(artist)/\(album)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let out = dir.appendingPathComponent(String(format: "%02d Faixa %d.flac", i % 12 + 1, i))
        if !FileManager.default.fileExists(atPath: out.path) { try FileManager.default.copyItem(at: sample, to: out) }
        let audio = try AudioFile(readingPropertiesAndMetadataFrom: out)
        let meta = audio.metadata
        // Um terço mantém a capa embutida (miniaturas na grade e nos Metadados).
        if i % 3 != 0 { meta.removeAllAttachedPictures() }
        // A cada 17 sem título, a cada 11 sem álbum, a cada 50 uma repetida (mesmo artista e título).
        meta.title = i % 17 == 0 ? nil : (i % 50 == 0 ? "Faixa 0" : "Faixa \(i)")
        meta.artist = i % 50 == 0 ? "Artista 0" : artist
        meta.albumTitle = i % 11 == 0 ? nil : album
        meta.albumArtist = artist
        meta.genre = genres[i % genres.count]
        meta.releaseDate = i % 5 == 0 ? nil : "\(1970 + i % 50)"
        meta.trackNumber = i % 12 + 1
        try audio.writeMetadata()
    }
    try? FileManager.default.removeItem(at: target.appendingPathComponent(".origem"))
    print("fixtures: \(count) arquivos em \(target.path)")
    exit(0)
}

let music = FileManager.default.urls(for: .musicDirectory, in: .userDomainMask)[0]
var arguments = Array(CommandLine.arguments.dropFirst())
if arguments.first == "--showcase" { showcaseMode = true; arguments.removeFirst() }
let target = arguments.first.map { URL(fileURLWithPath: $0) }
    ?? music.appendingPathComponent("Wineup Demo", isDirectory: true)
try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

var made: [String: URL] = [:]
for (i, t) in (showcaseMode ? showcaseCatalog : catalog).enumerated() {
    let url = try write(t, index: i, to: target)
    made[t.title] = url
    print("faixa: \(url.lastPathComponent)")
}

let override = ProcessInfo.processInfo.environment["WINEUP_LIBRARY_PATH"]
let db = try LibraryDatabase(path: override ?? LibraryDatabase.defaultPath())
// Em testes (WINEUP_DEFAULT_FOLDER), não adiciona ~/Music: só a pasta da demonstração.
if ProcessInfo.processInfo.environment["WINEUP_DEFAULT_FOLDER"] == nil {
    _ = try? LibraryBootstrap.ensureDefaultRoot(database: db)
}
let rootStore = LibraryRootStore(db: db)
var roots = try rootStore.roots()
// A demo fica dentro de ~/Music; só adiciona raiz própria se ela não estiver coberta.
if !roots.contains(where: { target.standardizedFileURL.path.hasPrefix($0.url.standardizedFileURL.path) }) {
    _ = try rootStore.addRoot(target)
    roots = try rootStore.roots()
}
let scanner = WineupLibrary.Scanner(database: db)
for root in roots {
    let result = try await scanner.scan(rootID: root.id) { _ in }
    print("varredura \(root.url.path): lidos \(result.read), ausentes \(result.missing)")
}

let collections = CollectionsStore(database: db)
func paths(_ titles: [String]) -> [String] { titles.compactMap { made[$0]?.standardizedFileURL.path } }
for existing in try collections.playlists() where ["Para Dirigir", "Relax de Domingo", "Noite de Sexta"].contains(existing.name) {
    try collections.deletePlaylist(id: existing.id)
}
let drive = try collections.createPlaylist(named: "Para Dirigir")
let added1 = try collections.append(paths: paths(["Rolha Solta", "Ondas Curtas", "Sinal Fraco", "Abertura do Vinho", "Café às Três"]), toPlaylist: drive.id)
let relax = try collections.createPlaylist(named: "Relax de Domingo")
let added2 = try collections.append(paths: paths(["Decantar", "Ladeira", "Estática Azul", "Última Taça"]), toPlaylist: relax.id)
print("playlists: Para Dirigir (\(added1)), Relax de Domingo (\(added2))")
if showcaseMode {
    let friday = try collections.createPlaylist(named: "Noite de Sexta")
    let added3 = try collections.append(paths: paths(["Céu de Neon", "Avenida 80", "Faísca", "Holograma", "Ruído Branco", "Chuva Ácida"]),
                                        toPlaylist: friday.id)
    print("playlist: Noite de Sexta (\(added3))")
}

let marks: [(String, String)] = [("Abertura do Vinho", "purple"), ("Última Taça", "purple"), ("Ondas Curtas", "blue"),
                                  ("Café às Três", "yellow"), ("Ladeira", "green"), ("Céu de Neon", "orange"),
                                  ("Varanda", "green"), ("Faísca", "red"), ("Holograma", "blue")]
for (title, color) in marks {
    if let path = paths([title]).first { try collections.setMark(path: path, color: color) }
}
print("tags de cor: \(try collections.markCounts())")
print("pronto: \(target.path)")
