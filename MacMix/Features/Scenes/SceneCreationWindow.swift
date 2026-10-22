import AppKit
import SwiftUI
import Observation

/// Shared shadow metrics for scene creation, appearance editing and action buttons.
enum ScenePresentationFeatures {
    static let shadowOpacity = 0.12
    static let shadowRadius: CGFloat = 7
    static let shadowOffset: CGFloat = 2
    static let shadowMargin: CGFloat = 64
}

@MainActor @Observable
final class SceneCreationWindowController {
    private(set) var isPresented = false
    private var window: SceneCreationNSWindow?
    private var timer: Timer?
    private var localMouseMonitor: Any?
    private var globalMouseMonitor: Any?
    private weak var anchor: NSView?
    private var sourceFrame = NSRect.zero
    private var closing = false
    private let transition = SceneWindowTransition()

    func present(from anchor: NSView, centeredIn page: NSView? = nil, scene: AudioScenePreset, defaultName: String, color: Color,
                 audio: AudioModel, sceneIndex: Int,
                 onComplete: @escaping (AudioScenePreset) -> Void) {
        guard !isPresented, let parent = anchor.window else { return }
        self.anchor = anchor
        sourceFrame = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        let visible = parent.screen?.visibleFrame ?? parent.frame
        let pageFrame = page.flatMap { view in
            view.window.map { $0.convertToScreen(view.convert(view.bounds, to: nil)) }
        } ?? parent.frame
        var target = NSRect(x: pageFrame.midX - 190, y: pageFrame.midY - 255, width: 380, height: 510)
        let settingsSize = CGSize(width: min(540, visible.width - 24), height: min(620, visible.height - 24))
        let centerX = min(max(target.midX, visible.minX + settingsSize.width / 2 + 12), visible.maxX - settingsSize.width / 2 - 12)
        let centerY = min(max(target.midY, visible.minY + settingsSize.height / 2 + 12), visible.maxY - settingsSize.height / 2 - 12)
        target.origin = NSPoint(x: centerX - 190, y: centerY - 255)
        let settingsFrame = NSRect(x: centerX - settingsSize.width / 2, y: centerY - settingsSize.height / 2,
                                   width: settingsSize.width, height: settingsSize.height)
        // Include the actual source button as well as the destination, including the whole shadow path.
        let canvas = target.union(settingsFrame).union(sourceFrame).insetBy(dx: -ScenePresentationFeatures.shadowMargin,
                                                      dy: -ScenePresentationFeatures.shadowMargin)
        transition.insets = EdgeInsets(top: canvas.maxY - target.maxY, leading: target.minX - canvas.minX,
                                       bottom: target.minY - canvas.minY, trailing: canvas.maxX - target.maxX)
        let panel = SceneCreationNSWindow(contentRect: canvas, styleMask: [.borderless], backing: .buffered, defer: false)
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        // Shadow follows the animated rounded surface, not the rectangular NSWindow.
        panel.hasShadow = false
        panel.isMovableByWindowBackground = false
        panel.isMovable = false
        panel.onCancel = { [weak self] in self?.dismiss() }
        transition.progress = 0
        transition.glyphProgress = 0
        transition.contentOpacity = 0
        transition.contentSize = CGSize(width: 380, height: 510)
        transition.settingsSize = settingsSize
        transition.source = CGRect(x: sourceFrame.minX - target.minX,
                                   y: target.maxY - sourceFrame.maxY,
                                   width: sourceFrame.width, height: sourceFrame.height)
        let root = SceneCreationWindowContent(scene: scene, defaultName: defaultName, color: color, transition: transition,
            audio: audio, sceneIndex: sceneIndex,
            onComplete: { [weak self] preset in self?.dismiss(fadesOut: true) { onComplete(preset) } },
            onCancel: { [weak self] in self?.dismiss() })
            .environment(\.hasStudioAccess, true)
            .tint(color)
        let host = NSHostingView(rootView: root)
        host.sizingOptions = []
        host.wantsLayer = true
        host.layer?.backgroundColor = NSColor.clear.cgColor
        host.layer?.masksToBounds = false

        panel.contentView = host
        window = panel
        isPresented = true
        closing = false
        parent.addChildWindow(panel, ordered: .above)
        panel.makeKeyAndOrderFront(nil)
        installOutsideClickMonitors()
        animate(to: target, opening: true)
    }

    func dismiss(fadesOut: Bool = false, completion: (() -> Void)? = nil) {
        guard let window, !closing else { return }
        closing = true
        removeOutsideClickMonitors()
        if let anchor, let parent = anchor.window {
            sourceFrame = parent.convertToScreen(anchor.convert(anchor.bounds, to: nil))
        }
        animate(to: sourceFrame, opening: false, fadesOut: fadesOut) { [weak self, weak window] in
            if let window { window.parent?.removeChildWindow(window) }
            window?.close()
            self?.window = nil
            self?.isPresented = false
            self?.closing = false
            completion?()
        }
    }

    private func installOutsideClickMonitors() {
        removeOutsideClickMonitors()
        localMouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] event in
            let shouldConsume = MainActor.assumeIsolated {
                guard let self, let window = self.window, !self.closing else { return false }
                guard window.attachedSheet == nil else { return false }
                let size = self.transition.contentSize
                let contentRect = NSRect(x: self.transition.insets.leading + (380 - size.width) / 2,
                                         y: self.transition.insets.bottom + (510 - size.height) / 2,
                                         width: size.width, height: size.height)
                let point = window.convertPoint(fromScreen: NSEvent.mouseLocation)
                if event.window !== window || !NSBezierPath(roundedRect: contentRect, xRadius: 24, yRadius: 24).contains(point) {
                    self.dismiss()
                    // Consume clicks in our transparent margin, pass other app-window clicks through.
                    return event.window === window
                }
                return false
            }
            return shouldConsume ? nil : event
        }
        globalMouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown, .otherMouseDown]) { [weak self] _ in
            Task { @MainActor in
                guard self?.window?.attachedSheet == nil else { return }
                self?.dismiss()
            }
        }
    }

    private func removeOutsideClickMonitors() {
        if let localMouseMonitor { NSEvent.removeMonitor(localMouseMonitor) }
        if let globalMouseMonitor { NSEvent.removeMonitor(globalMouseMonitor) }
        localMouseMonitor = nil
        globalMouseMonitor = nil
    }

    private func animate(to target: NSRect, opening: Bool, fadesOut: Bool = false, completion: (() -> Void)? = nil) {
        timer?.invalidate()
        guard let window else { return }
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        let duration = fadesOut ? 0.18 : (reduceMotion ? 0.16 : 0.62)
        let start = Date.timeIntervalSinceReferenceDate
        let initial = transition.progress
        let destination = opening ? 1.0 : 0.0
        if !opening && !fadesOut {
            transition.source = CGRect(x: target.minX - window.frame.minX - transition.insets.leading,
                y: window.frame.maxY - target.maxY - transition.insets.top, width: target.width, height: target.height)
        }
        let tick = Timer(timeInterval: 1.0 / 120, repeats: true) { [weak self, weak window] timer in
            MainActor.assumeIsolated {
                guard let self, let window else { timer.invalidate(); return }
                let t = min(1, (Date.timeIntervalSinceReferenceDate - start) / duration)
                if fadesOut {
                    window.alphaValue = 1 - t * t * (3 - 2 * t)
                } else {
                    // Restore the original spring in both directions.
                    let spring = t == 1 ? 1 : 1 - exp(-8 * t) * cos(8 * t)
                    self.transition.progress = reduceMotion ? destination : initial + (destination - initial) * spring
                    // Follow the container exactly until its first arrival, then hold the glyph
                    // at the destination throughout every subsequent overshoot and rebound.
                    let reachedDestination = reduceMotion || t >= .pi / 16
                    self.transition.glyphProgress = reachedDestination ? destination : self.transition.progress
                    self.transition.contentOpacity = max(0, min(1, (self.transition.progress - 0.55) / 0.45))
                    window.alphaValue = reduceMotion ? (opening ? t : 1 - t) : 1
                }
                if t == 1 {
                    timer.invalidate()
                    self.timer = nil
                    completion?()
                }
            }
        }
        timer = tick
        RunLoop.main.add(tick, forMode: .common)
    }
}

private final class SceneCreationNSWindow: NSWindow {
    var onCancel: (() -> Void)?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func cancelOperation(_ sender: Any?) { onCancel?() }
}

@MainActor @Observable
private final class SceneWindowTransition {
    var progress: Double = 0
    var glyphProgress: Double = 0
    var contentOpacity: Double = 0
    var source: CGRect = .zero
    var insets = EdgeInsets()
    var contentSize = CGSize(width: 380, height: 510)
    var settingsSize = CGSize(width: 540, height: 620)
}

private struct SceneCreationWindowContent: View {
    @State var scene: AudioScenePreset
    let defaultName: String
    let color: Color
    let transition: SceneWindowTransition
    let audio: AudioModel
    let sceneIndex: Int
    let onComplete: (AudioScenePreset) -> Void
    let onCancel: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            let p = transition.progress
            let source = transition.source
            let width = source.width + (transition.contentSize.width - source.width) * p
            let height = source.height + (transition.contentSize.height - source.height) * p
            let centerX = source.midX + (190 - source.midX) * p
            let centerY = source.midY + (255 - source.midY) * p
            let radius = max(24, source.width / 2 + (24 - source.width / 2) * p)
            SceneWindowSurface(cornerRadius: radius)
                .frame(width: max(1, width), height: max(1, height))
                .modifier(SceneSurfaceShadow())
                .position(x: centerX, y: centerY)
            SceneCreationWizard(scene: $scene, defaultName: defaultName, color: color,
                                transition: transition, audio: audio, sceneIndex: sceneIndex,
                                onComplete: onComplete, onCancel: onCancel)
                .frame(width: transition.contentSize.width, height: transition.contentSize.height)
                .opacity(transition.contentOpacity)
                .allowsHitTesting(p > 0.98 && transition.contentOpacity > 0.98)
                .clipShape(RoundedRectangle(cornerRadius: 24))
                .position(x: 190, y: 255)
            // Return the glyph inside the shrinking surface before handing back to the source button.
            Image(systemName: "plus")
                .font(.system(size: source.width * 0.4, weight: .medium))
                .foregroundStyle(.primary)
                .opacity(max(0, min(1, 1 - transition.glyphProgress / 0.22)))
                .position(x: source.midX + (190 - source.midX) * transition.glyphProgress,
                          y: source.midY + (255 - source.midY) * transition.glyphProgress)
                .allowsHitTesting(false)
                .accessibilityHidden(true)

        }
        .frame(width: 380, height: 510)
        .padding(transition.insets)
    }
}

private struct SceneCreationWizard: View {
    @Binding var scene: AudioScenePreset
    let defaultName: String
    let color: Color
    let transition: SceneWindowTransition
    let audio: AudioModel
    let sceneIndex: Int
    let onComplete: (AudioScenePreset) -> Void
    let onCancel: () -> Void
    @State private var showsSettings = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var backAction: (() -> Void)? {
        guard showsSettings else { return nil }
        return { goBack() }
    }

    var body: some View {
        ZStack(alignment: .top) {
            ZStack {
                if showsSettings {
                    AudioSceneEditor(scene: $scene, sceneIndex: sceneIndex, audio: audio, isCreating: true)
                        .transition(reduceMotion ? .opacity : .move(edge: .trailing).combined(with: .opacity))
                } else {
                    SceneAppearanceEditor(scene: $scene, defaultName: defaultName,
                                          actionColor: color, reservesActionsSpace: true)
                        .transition(reduceMotion ? .opacity : .move(edge: .leading).combined(with: .opacity))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
            SceneCreationActions(color: color, onComplete: advance, onCancel: onCancel,
                                 isValid: true, isNextStep: !showsSettings,
                                 onBack: backAction)
                .padding(.horizontal, 16)
                .padding(.top, 12)
        }
    }

    private func goBack() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        withAnimation(.smooth(duration: reduceMotion ? 0.16 : 0.32)) {
            transition.contentSize = CGSize(width: 380, height: 510)
            showsSettings = false
        }
    }

    private func advance() {
        NSApp.keyWindow?.makeFirstResponder(nil)
        if showsSettings {
            var preset = scene
            preset.name = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
            onComplete(preset)
        } else {
            withAnimation(.smooth(duration: reduceMotion ? 0.16 : 0.32)) {
                transition.contentSize = transition.settingsSize
                showsSettings = true
            }
        }
    }
}

private struct SceneWindowSurface: View {
    let cornerRadius: CGFloat
    var body: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        if #available(macOS 26.0, *), AppAppearanceFeatures.usesLiquidGlass {
            Color.clear.glassEffect(.regular, in: shape)
        } else {
            shape.fill(.ultraThinMaterial)
        }
    }
}

struct SceneWindowAnchor: NSViewRepresentable {
    let onResolve: (NSView) -> Void
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { onResolve(view) }
        return view
    }
    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct SceneSurfaceShadow: ViewModifier {
    func body(content: Content) -> some View {
        content.shadow(color: .black.opacity(ScenePresentationFeatures.shadowOpacity),
                       radius: ScenePresentationFeatures.shadowRadius,
                       y: ScenePresentationFeatures.shadowOffset)
    }
}
