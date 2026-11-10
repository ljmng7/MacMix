import SwiftUI

/// Keep short panels at their natural height and scroll only when the expanded
/// content would exceed the space between the menu bar and the Dock.
struct MenuBarPanelViewport<Content: View>: View {
    let maximumHeight: CGFloat
    let content: Content
    let onHeightChange: (CGFloat) -> Void
    @State private var contentHeight: CGFloat = 0

    init(maximumHeight: CGFloat, onHeightChange: @escaping (CGFloat) -> Void = { _ in },
         @ViewBuilder content: () -> Content) {
        self.maximumHeight = max(1, maximumHeight)
        self.onHeightChange = onHeightChange
        self.content = content()
    }

    var body: some View {
        ScrollView(.vertical) {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { height in
                    let measured = max(1, ceil(height))
                    if contentHeight != measured { contentHeight = measured }
                    onHeightChange(measured)
                }
        }
        .scrollBounceBehavior(.basedOnSize)
        .scrollDisabled(contentHeight > 0 && contentHeight <= maximumHeight)
        .frame(height: contentHeight > 0 ? min(contentHeight, maximumHeight) : nil)
        .frame(maxHeight: maximumHeight)
    }
}
