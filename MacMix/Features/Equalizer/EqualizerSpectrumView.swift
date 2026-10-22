import AppKit
import SwiftUI
import MacMixStudio

/// Only this tiny native drawing surface refreshes with audio. Parent SwiftUI
/// rows and EQ handles do not observe spectrum frames.
struct EqualizerSpectrumView: NSViewRepresentable {
    let targetID: String
    let isEnabled: Bool

    func makeNSView(context: Context) -> EqualizerSpectrumNSView {
        EqualizerSpectrumNSView()
    }
    func updateNSView(_ view: EqualizerSpectrumNSView, context: Context) {
        view.configure(targetID: targetID, enabled: isEnabled)
    }
    static func dismantleNSView(_ view: EqualizerSpectrumNSView, coordinator: ()) {
        view.stop()
    }
}

final class EqualizerSpectrumNSView: NSView {
    private let subscription = UUID()
    private var targetID = ""
    private var enabled = false
    private var samplingTask: Task<Void, Never>?
    private var observers: [NSObjectProtocol] = []
    private var visibilityObservation: NSKeyValueObservation?
    private var hasSpectrumFrame = false
    private var bars = [Float](repeating: 0, count: Int(MacMixEQSpectrumBarCount))
    private let spectrumGradient = CAGradientLayer()
    private let spectrumMask = CAShapeLayer()
    private var renderedSize = CGSize.zero
    private static let colors = [
        NSColor(srgbRed: 0.93, green: 0.98, blue: 0.28, alpha: 1),
        NSColor(srgbRed: 0.45, green: 1, blue: 0.56, alpha: 1),
        NSColor(srgbRed: 0, green: 1, blue: 0.95, alpha: 1),
        NSColor(srgbRed: 0, green: 174.0/255, blue: 1, alpha: 1),
        NSColor(srgbRed: 0, green: 1, blue: 0.95, alpha: 1),
        NSColor(srgbRed: 0.45, green: 1, blue: 0.56, alpha: 1),
        NSColor(srgbRed: 0.93, green: 0.98, blue: 0.28, alpha: 1)
    ]

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        configureLayers()
    }
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        configureLayers()
    }
    private func configureLayers() {
        wantsLayer = true
        spectrumGradient.colors = Self.colors.map(\.cgColor)
        spectrumGradient.locations = [0, 0.20, 0.34, 0.50, 0.66, 0.80, 1]
        spectrumGradient.startPoint = CGPoint(x: 0.5, y: 0)
        spectrumGradient.endPoint = CGPoint(x: 0.5, y: 1)
        spectrumGradient.mask = spectrumMask
        spectrumGradient.isHidden = true
        layer?.addSublayer(spectrumGradient)
    }

    override var isFlipped: Bool { true }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    func configure(targetID: String, enabled: Bool) {
        if self.targetID != targetID {
            stop()
            self.targetID = targetID
        }
        self.enabled = enabled
        updateActivity()
    }
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        removeObservers()
        visibilityObservation = nil
        if let window {
            visibilityObservation = window.observe(\.isVisible, options: [.new]) { [weak self] _, _ in
                Task { @MainActor [weak self] in self?.updateActivity() }
            }
            for name in [NSWindow.didChangeOcclusionStateNotification,
                         NSWindow.didMiniaturizeNotification, NSWindow.didDeminiaturizeNotification,
                         NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification,
                         NSWindow.willCloseNotification] {
                observers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                    Task { @MainActor [weak self] in self?.updateActivity() }
                })
            }
        }
        if let clip = enclosingScrollView?.contentView {
            clip.postsBoundsChangedNotifications = true
            observers.append(NotificationCenter.default.addObserver(forName: NSView.boundsDidChangeNotification, object: clip, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateActivity() }
            })
        }
        updateActivity()
    }
    override func layout() {
        super.layout()
        updateActivity()
        if bounds.size != renderedSize { renderBars() }
    }
    private func updateActivity() {
        guard enabled, !targetID.isEmpty, let window, window.isVisible,
              window.occlusionState.contains(.visible), !window.isMiniaturized,
              !isHiddenOrHasHiddenAncestor, !visibleRect.isEmpty else {
            stop()
            return
        }
        guard samplingTask == nil else { return }
        let target = targetID
        AppAudioMixer.shared.setMetering(true, for: target, subscription: subscription)
        samplingTask = Task { [weak self] in
            while !Task.isCancelled {
                let values = await AppAudioMixer.shared.spectrum(for: target)
                guard !Task.isCancelled, self != nil else { return }
                self?.updateBars(values)
                // The supplied 120 fps recording changes spectrum about every third
                // frame. Cap this isolated surface at 40 Hz, not the display rate.
                do { try await Task.sleep(for: .milliseconds(25)) } catch { return }
            }
        }
    }
    private func updateBars(_ values: [Float]) {
        guard !values.isEmpty else {
            if hasSpectrumFrame {
                hasSpectrumFrame = false
                bars = Array(repeating: 0, count: Int(MacMixEQSpectrumBarCount))
                renderBars()
            }
            return
        }
        var changed = !hasSpectrumFrame
        hasSpectrumFrame = true
        for index in bars.indices {
            let level = values.indices.contains(index) ? max(0, min(1, values[index])) : 0
            // Display contrast follows the reference: clear peaks and quiet valleys,
            // rather than filling most of the chart for every audible bin.
            let target = level * level
            let old = bars[index]
            let next = old + (target - old) * (target > old ? 0.75 : 0.35)
            bars[index] = next < 0.005 ? 0 : next
            changed = changed || abs(old - bars[index]) > 0.0005
        }
        if changed { renderBars() }
    }
    func stop() {
        if samplingTask != nil {
            samplingTask?.cancel()
            samplingTask = nil
            AppAudioMixer.shared.setMetering(false, for: targetID, subscription: subscription)
        }
        if hasSpectrumFrame || bars.contains(where: { $0 != 0 }) {
            hasSpectrumFrame = false
            bars = Array(repeating: 0, count: Int(MacMixEQSpectrumBarCount))
            renderBars()
        }
    }
    private func removeObservers() {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers.removeAll()
    }
    deinit {
        samplingTask?.cancel()
        AppAudioMixer.shared.setMetering(false, for: targetID, subscription: subscription)
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }
    private func renderBars() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        defer { CATransaction.commit() }
        renderedSize = bounds.size
        spectrumGradient.frame = bounds
        spectrumMask.frame = spectrumGradient.bounds
        spectrumGradient.isHidden = !hasSpectrumFrame
        guard hasSpectrumFrame, bounds.width > 0, bounds.height > 0 else {
            spectrumMask.path = nil
            return
        }
        let path = CGMutablePath()
        let step = bounds.width / CGFloat(bars.count)
        let width = max(1, step * 0.82)
        for (index, value) in bars.enumerated() {
            let height = max(width, CGFloat(value) * bounds.height * 0.92)
            let rect = CGRect(x: CGFloat(index) * step + (step - width) / 2,
                              y: (bounds.height - height) / 2, width: width, height: height)
            path.addRoundedRect(in: rect, cornerWidth: width / 2, cornerHeight: width / 2)
        }
        // Update only the mask; Core Animation reuses the gradient instead of
        // repainting an AppKit view (and notifying its entire window) every frame.
        spectrumMask.path = path
    }
}
