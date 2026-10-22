import UniformTypeIdentifiers
import AppKit
import Foundation
import WineupCore
import WineupLibrary

extension PlayerState {

    func setMark(_ color: MarkColor?, on track: Track) {
        guard let url = track.url else { return }
        browser.setMark(color, path: url.path)
        let replaced = Track(id: track.id, artist: track.artist, title: track.title, duration: track.duration,
                             mark: color, url: track.url, album: track.album, year: track.year)
        tracks = tracks.map { $0.id == track.id ? replaced : $0 }
    }

    func addToPlaylist(_ track: Track, playlistID: Int64) {
        guard let url = track.url else { return }
        browser.add(paths: [url.path], toPlaylist: playlistID)
    }

    /// Pede o nome e cria a playlist (opcionalmente já com uma faixa).
    func newPlaylist(with track: Track?) {
        guard let name = TextPrompt.ask(title: "Nova playlist", value: "Nova playlist") else { return }
        if let created = browser.createPlaylist(named: name, paths: track?.url.map { [$0.path] } ?? []) {
            statusMessage = "Playlist \u{201C}\(created.name)\u{201D} criada."
        }
    }

    /// Remove a faixa da playlist aberta (no banco) ou só da lista atual.
    func removeFromList(_ track: Track) {
        if let id = browser.openPlaylistID, let url = track.url {
            browser.remove(path: url.path, fromPlaylist: id)
            tracks = tracks.filter { $0.id != track.id }
        } else {
            tracks = tracks.filter { $0.id != track.id }
        }
        if selectedID == track.id { selectedID = nil }
    }

    func playSelected() {
        let pick = selectedID.flatMap { id in visibleTracks.first { $0.id == id } } ?? visibleTracks.first
        if let pick { play(pick, from: visibleTracks) }
    }

    func removeSelected() {
        guard let id = selectedID, let track = tracks.first(where: { $0.id == id }) else { return }
        removeFromList(track)
    }
}

extension PlayerState {
    /// Abre a pasta na lista e toca a primeira faixa.
    func playFolder(_ url: URL) {
        browser.go(folder: url)
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let first = TrackLoader.audioURLs(in: [url]).first.map(TrackLoader.track(url:))
            DispatchQueue.main.async {
                guard let self, let first else { return }
                let match = self.tracks.first { $0.url == first.url } ?? first
                self.play(match)
            }
        }
    }
}

extension PlayerState {
    /// Coloca a faixa logo depois da que está tocando.
    func playNext(_ track: Track) {
        guard let current = queue.currentIndex else { play(track, from: visibleTracks); return }
        queue = queue.inserting([track], at: current + 1)
        reenqueue()
        statusMessage = "\u{201C}\(track.title)\u{201D} toca a seguir."
    }

    /// Abre todas as músicas da biblioteca na lista.
    func showAllTracks() {
        browser.setView(.songs)
    }
}

extension PlayerState {
    /// Toca um grupo inteiro (álbum, artista, gênero, playlist ou tag).
    func playGroup(_ group: ViewGroup) {
        let items = browser.tracks(for: group)
        if let first = items.first { play(first, from: items) }
    }

    /// Pergunta a pasta padrão de músicas (primeira abertura). Cancelar usa ~/Music.
    func askDefaultFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.directoryURL = NavPlaces.music
        panel.prompt = "Usar esta pasta"
        panel.message = "Escolha sua pasta de músicas. O Wineup abre nela e você navega a partir dela."
        let url = panel.runModal() == .OK ? (panel.url ?? NavPlaces.music) : NavPlaces.music
        makeDefaultFolder(url)
    }

    /// Define a pasta padrão e garante que ela esteja na biblioteca (indexada).
    func makeDefaultFolder(_ url: URL) {
        browser.setDefaultFolder(url)
        if !browser.isIndexed(url) { Task { await library.addFolders([url]) } }
        statusMessage = "Pasta padrão: \(NavPlaces.displayPath(url))"
    }
}

// MARK: M3U / M3U8

extension PlayerState {
    /// Abre uma playlist M3U/M3U8 na lista (faixas que existem no disco).
    func openM3U(_ file: URL) {
        do {
            let entries = try M3U.read(file)
            let present = entries.filter { FileManager.default.fileExists(atPath: $0.url.path) }
            let items = present.map { browser.track(atPath: $0.url.path) }
            showTracks(title: file.deletingPathExtension().lastPathComponent, items: items)
            let missing = entries.count - present.count
            statusMessage = missing == 0 ? "Playlist aberta: \(items.count) faixas."
                : "Playlist aberta: \(items.count) faixas (\(missing) não encontradas)."
        } catch {
            statusMessage = "Não foi possível ler a playlist \(file.lastPathComponent)."
        }
    }

    /// Importa um M3U como playlist do Wineup (faixas que estão na biblioteca).
    func importM3U() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.init(filenameExtension: "m3u")!, .init(filenameExtension: "m3u8")!]
        panel.message = "Escolha uma playlist M3U/M3U8 para importar"
        guard panel.runModal() == .OK, let file = panel.url, let entries = try? M3U.read(file) else { return }
        let paths = entries.map(\.url.path)
        let name = file.deletingPathExtension().lastPathComponent
        if let created = browser.createPlaylist(named: name, paths: paths) {
            let added = browser.allPlaylists().first { $0.id == created.id }?.paths.count ?? 0
            statusMessage = "Playlist \u{201C}\(created.name)\u{201D} importada: \(added) de \(entries.count) faixas na biblioteca."
        }
        openM3U(file)
    }

    /// Exporta a lista atual como .m3u8 (UTF-8).
    func exportM3U() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(listTitle).m3u8"
        panel.message = "Exportar a lista atual como playlist M3U8"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try M3U.write(visibleTracks).write(to: url, atomically: true, encoding: .utf8)
            statusMessage = "Playlist exportada: \(visibleTracks.count) faixas."
        } catch {
            statusMessage = "Não foi possível exportar a playlist."
        }
    }
}

// MARK: Fila

extension PlayerState {
    /// Na visão Fila, tocar uma faixa só muda a posição (não remonta a fila).
    func playFromList(_ track: Track, list: [Track]) {
        if browser.view == .queue, let index = queue.items.firstIndex(where: { $0.id == track.id }) {
            queue = queue.selecting(index: index)
            startCurrentPublic()
        } else {
            play(track, from: list)
        }
    }

    /// Reordena a fila (arrastar na visão Fila).
    func moveInQueue(from source: Int, to destination: Int) {
        guard queue.items.indices.contains(source), source != destination else { return }
        queue = queue.moving(from: IndexSet(integer: source), to: destination > source ? destination + 1 : destination)
        reenqueue()
    }

    func removeFromQueue(_ track: Track) {
        guard let index = queue.items.firstIndex(where: { $0.id == track.id }), index != queue.currentIndex else { return }
        queue = queue.removing(at: index)
        reenqueue()
    }
}
