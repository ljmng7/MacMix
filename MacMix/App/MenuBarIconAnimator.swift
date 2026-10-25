import AppKit

/// One state of the menu bar icon: a symbol and, for the volume symbol, its
/// variable value.
struct MenuBarIcon: Equatable {
    let symbolName: String
    var variableValue: Double?
}

/// Draws the menu bar icon in an image view laid over the status item button.
/// MenuBarExtra hands its label to the button as a static image, which drops
/// symbol transitions; the label therefore shows a transparent placeholder of
/// the same size and this view animates mute changes like the system item.
@MainActor
final class MenuBarIconAnimator {
    /// When and how fast the symbol re-centres during a mute change, measured
    /// from the system item: it moves while the shared speaker is shrunk, after
    /// the waves (muting) or the slash (unmuting) have mostly drawn off.
    private struct Recentring {
        let delay: TimeInterval
        let duration: TimeInterval

        static let muting = Recentring(delay: 0.18, duration: 0.1)
        static let unmuting = Recentring(delay: 0.34, duration: 0.08)
    }

    /// How long a mute transition runs; level updates that arrive meanwhile
    /// wait for it so they do not cut it short.
    private static let transitionDuration: Duration = .milliseconds(500)

    private let imageView = NSImageView()
    private var leadingConstraint: NSLayoutConstraint?
    /// The latest requested icon, and the one currently on screen.
    private var current: MenuBarIcon?
    private var displayed: MenuBarIcon?
    private var transitionTask: Task<Void, Never>?
    private var attachRetryTask: Task<Void, Never>?

    init() {
        imageView.imageScaling = .scaleNone
        // Magic Replace keeps the shared speaker in place and lays the old and
        // new symbols out from their leading edges. The symbol is therefore
        // leading-aligned in a fixed-width view, and the view is offset to
        // centre the current symbol.
        imageView.imageAlignment = .alignLeft
        imageView.translatesAutoresizingMaskIntoConstraints = false
        for orientation in [NSLayoutConstraint.Orientation.horizontal, .vertical] {
            imageView.setContentHuggingPriority(.defaultLow, for: orientation)
            imageView.setContentCompressionResistancePriority(.defaultLow, for: orientation)
        }
        imageView.setAccessibilityElement(false)
    }

    func attach(to button: NSStatusBarButton) {
        guard imageView.superview !== button else { return }
        attachRetryTask?.cancel()
        attachRetryTask = nil
        transitionTask?.cancel()
        transitionTask = nil
        imageView.removeFromSuperview()
        button.addSubview(imageView)
        let leading = imageView.leadingAnchor.constraint(equalTo: button.leadingAnchor)
        leadingConstraint = leading
        NSLayoutConstraint.activate([
            leading,
            imageView.widthAnchor.constraint(equalTo: button.widthAnchor),
            imageView.topAnchor.constraint(equalTo: button.topAnchor),
            imageView.bottomAnchor.constraint(equalTo: button.bottomAnchor)
        ])
        displayed = nil
        if let current { apply(current) }
    }

    func show(_ icon: MenuBarIcon) {
        guard icon != current else { return }
        current = icon
        guard attachIfNeeded(), transitionTask == nil else {
            // Applied once attached, or when the running transition ends.
            return
        }
        apply(icon)
    }

    private func apply(_ icon: MenuBarIcon) {
        let previous = displayed
        displayed = icon
        guard let image = Self.image(for: icon) else { return }
        let offset = centringOffset(for: image)

        // Only a symbol change animates; level changes just redraw the waves.
        guard let previous, previous.symbolName != icon.symbolName,
              !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else {
            imageView.image = image
            leadingConstraint?.constant = offset
            return
        }
        if #available(macOS 15.0, *) {
            imageView.setSymbolImage(image, contentTransition: .replace.magic(fallback: .downUp))
        } else {
            imageView.setSymbolImage(image, contentTransition: .replace.downUp)
        }

        // Re-centre while the speaker is shrunk, as the system item does, so
        // the move hides inside the transition instead of sliding visibly.
        let timing: Recentring = image.size.width < (Self.image(for: previous)?.size.width ?? 0)
            ? .muting : .unmuting
        transitionTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(timing.delay))
            guard !Task.isCancelled, let self else { return }
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = timing.duration
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                // Animate only the constraint; implicit animation would also
                // stretch the layers of the running symbol transition.
                self.leadingConstraint?.animator().constant = offset
            }, completionHandler: nil)

            try? await Task.sleep(for: Self.transitionDuration - .seconds(timing.delay))
            guard !Task.isCancelled else { return }
            transitionTask = nil
            if let current, current != displayed { apply(current) }
        }
    }

    /// The status item introspection runs once at launch and can precede the
    /// runtime, so look the button up directly, retrying until it exists.
    private func attachIfNeeded() -> Bool {
        guard imageView.superview == nil else { return true }
        if let button = Self.findStatusBarButton() {
            attach(to: button)
            return true
        }
        guard attachRetryTask == nil else { return false }
        attachRetryTask = Task { @MainActor [weak self] in
            for _ in 0..<20 {
                try? await Task.sleep(for: .milliseconds(250))
                guard !Task.isCancelled, let self else { return }
                if let button = Self.findStatusBarButton() {
                    attach(to: button)
                    return
                }
            }
        }
        return false
    }

    /// Leading inset that centres `image` in the status item.
    private func centringOffset(for image: NSImage) -> CGFloat {
        let width = imageView.superview?.bounds.width ?? MenuBarIconMetrics.statusItemLength
        return (width - image.size.width) / 2
    }

    static func image(for icon: MenuBarIcon) -> NSImage? {
        let image = if let value = icon.variableValue {
            NSImage(systemSymbolName: icon.symbolName, variableValue: value, accessibilityDescription: nil)
        } else {
            NSImage(systemSymbolName: icon.symbolName, accessibilityDescription: nil)
        }
        return image?.withSymbolConfiguration(MenuBarIconMetrics.symbolConfiguration)
    }

    private static func findStatusBarButton() -> NSStatusBarButton? {
        NSApp.windows
            .first { $0.className.contains("NSStatusBarWindow") }?
            .contentView
            .flatMap { view in
                view as? NSStatusBarButton ?? view.subviews.lazy.compactMap { $0 as? NSStatusBarButton }.first
            }
    }
}
