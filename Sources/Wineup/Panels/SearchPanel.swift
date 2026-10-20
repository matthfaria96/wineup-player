import SwiftUI

struct SearchPanel: View {
    @ObservedObject var state: PlayerState

    @Environment(\.theme) private var theme

    var body: some View {
        Panel(title: "Search") {
            VStack(spacing: 8) {
                field
                if state.searchResults.isEmpty {
                    Text(state.query.isEmpty ? "Digite para buscar na biblioteca" : "Nada encontrado")
                        .font(.system(size: 12))
                        .foregroundStyle(theme.mutedText)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(state.searchResults.enumerated()), id: \.element.id) { offset, track in
                                TrackRow(
                                    track: track,
                                    index: offset + 1,
                                    isCurrent: track.id == state.currentID,
                                    isSelected: track.id == state.selectedID,
                                    showsDuration: false
                                )
                                .onTapGesture(count: 2) { state.play(track) }
                                .onTapGesture { state.selectedID = track.id }
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.bottom, 10)
        }
    }

    private var field: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(theme.mutedText)
            TextField("", text: $state.query)
                .textFieldStyle(.plain)
                .foregroundStyle(theme.text)
            if !state.query.isEmpty {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(theme.mutedText)
                    .onTapGesture { state.query = "" }
            }
        }
        .font(.system(size: 14))
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 7).fill(Color.white.opacity(0.06)))
        .overlay(RoundedRectangle(cornerRadius: 7).stroke(theme.panelBorder, lineWidth: 1))
    }
}
