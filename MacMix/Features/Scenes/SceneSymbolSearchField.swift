import SwiftUI

struct SceneSymbolSearchField: View {
    @Binding var text: String
    @FocusState private var isFocused: Bool

    var body: some View {
        field.background(.quaternary.opacity(0.5), in: Capsule())
    }

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search Symbols", text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .frame(maxWidth: .infinity, minHeight: 34)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }
                    .buttonStyle(.plain).accessibilityLabel("Clear Search")
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 34)
        .contentShape(Capsule())
        .onTapGesture { isFocused = true }
    }
}
