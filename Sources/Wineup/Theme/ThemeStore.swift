import WineupLibrary

extension ThemeStore {
    /// Tema pronto para desenhar (o Grafite se o id não existe mais).
    func theme(_ id: String) -> Theme { Theme(file(id) ?? .graphite) }
}
