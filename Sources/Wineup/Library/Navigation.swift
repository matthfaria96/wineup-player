import AppKit
import Foundation
import WineupCore

/// Um passo do histórico de navegação.
enum NavEntry: Equatable {
    case library(BrowseMode)
    case group(BrowseGroup)
    case folder(URL)
}

enum NavLocation: Equatable {
    case library
    case folder(URL)
}

/// Locais padrão e favoritos do seletor de local.
enum NavPlaces {
    static let favoritesKey = "favoriteLocations"

    static var music: URL { FileManager.default.urls(for: .musicDirectory, in: .userDomainMask)[0] }
    static var downloads: URL { FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0] }

    static func loadFavorites() -> [URL] {
        (UserDefaults.standard.stringArray(forKey: favoritesKey) ?? []).map { URL(fileURLWithPath: $0) }
    }

    static func saveFavorites(_ urls: [URL]) {
        UserDefaults.standard.set(urls.map(\.path), forKey: favoritesKey)
    }

    /// Nome amigável: "~" para a pasta pessoal.
    static func displayPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }
}

extension LibraryBrowser {
    // MARK: Navegação

    func record(_ entry: NavEntry) {
        if !isReplaying, let current = currentEntry, current != entry {
            backStack.append(current)
            forwardStack = []
        }
        currentEntry = entry
    }

    func goBack() {
        guard let previous = backStack.popLast() else { return }
        if let current = currentEntry { forwardStack.append(current) }
        replay(previous)
    }

    func goForward() {
        guard let next = forwardStack.popLast() else { return }
        if let current = currentEntry { backStack.append(current) }
        replay(next)
    }

    private func replay(_ entry: NavEntry) {
        isReplaying = true
        switch entry {
        case .library(let mode): goLibrary(mode)
        case .group(let group): open(group)
        case .folder(let url): goFolder(url)
        }
        currentEntry = entry
        isReplaying = false
    }

    func goLibrary(_ mode: BrowseMode) {
        record(.library(mode))
        location = .library
        currentGroupTitle = nil
        showingGroups = true
        if self.mode != mode { self.mode = mode } else { reload() }
    }

    func goFolder(_ url: URL) {
        record(.folder(url))
        location = .folder(url)
        showingGroups = false
        currentGroupTitle = nil
        Task.detached(priority: .userInitiated) { [weak self] in
            let listing = Self.listFolder(url)
            await MainActor.run {
                guard let self, self.location == .folder(url) else { return }
                self.subfolders = listing.folders
                self.onOpenTracks?(url.lastPathComponent, listing.tracks)
            }
        }
    }

    var canGoUp: Bool {
        switch location {
        case .library: return !showingGroups
        case .folder(let url): return url.path != "/"
        }
    }

    func goUp() {
        switch location {
        case .library: if !showingGroups { goLibrary(mode) }
        case .folder(let url): goFolder(url.deletingLastPathComponent())
        }
    }

    func chooseOtherFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.message = "Escolha uma pasta para navegar"
        if panel.runModal() == .OK, let url = panel.url { goFolder(url) }
    }

    // MARK: Favoritos

    var currentFolder: URL? {
        if case .folder(let url) = location { return url }
        return nil
    }

    var isCurrentFavorite: Bool { currentFolder.map { favorites.contains($0) } ?? false }

    func toggleFavorite() {
        guard let url = currentFolder else { return }
        favorites = isCurrentFavorite ? favorites.filter { $0 != url } : favorites + [url]
        NavPlaces.saveFavorites(favorites)
    }

    func removeFavorite(_ url: URL) {
        favorites = favorites.filter { $0 != url }
        NavPlaces.saveFavorites(favorites)
    }

    // MARK: Leitura da pasta (fora da main thread)

    private static func listFolder(_ url: URL) -> (folders: [URL], tracks: [Track]) {
        let items = (try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        let allowed = TrackLoader.supportedExtensions
        let folders = items.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true && $0.pathExtension != "app" }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
        let files = items.filter { allowed.contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedStandardCompare($1.lastPathComponent) == .orderedAscending }
            .prefix(2000)
        return (folders, files.map(TrackLoader.track(url:)))
    }
}
