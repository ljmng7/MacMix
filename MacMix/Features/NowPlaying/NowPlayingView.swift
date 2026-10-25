//
//  NowPlayingView.swift
//  MacMix
//

import AppKit
import SwiftUI

struct NowPlayingSection: View {
    let model: NowPlayingModel
    var topContentInset: CGFloat? = nil
    @State private var expandedSessionID: NowPlayingSessionState.ID?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(model.sessions) { session in
                NowPlayingRow(
                    session: session,
                    isExpanded: expandedSessionID == session.id,
                    topContentInset: session.id == model.sessions.first?.id ? topContentInset : nil,
                    onToggleExpanded: {
                        DiagnosticLog.shared.record("interface", "now_playing_expansion", fields: [
                            "expanded": String(expandedSessionID != session.id)])
                        // Fitted to the supplied system Now Playing recording:
                        // gentle onset, faster middle, and a soft stop.
                        withAnimation(.timingCurve(0.3, 0.3, 0.3, 1, duration: 0.27)) {
                            expandedSessionID = expandedSessionID == session.id
                                ? nil
                                : session.id
                        }
                    },
                    onOpenApplication: {
                        model.openApplication(for: session)
                    },
                    onPrevious: {
                        model.playPrevious(for: session)
                    },
                    onTogglePlayback: {
                        model.togglePlayback(for: session)
                    },
                    onNext: {
                        model.playNext(for: session)
                    },
                    onSeek: { position in
                        model.seek(to: position, for: session)
                    }
                )

                if session.id != model.sessions.last?.id {
                    Divider()
                }
            }

            Divider()
        }
        .onAppear {
            model.refresh()
        }
    }
}

private struct NowPlayingRow: View {
    let session: NowPlayingSessionState
    let isExpanded: Bool
    let topContentInset: CGFloat?
    let onToggleExpanded: () -> Void
    let onOpenApplication: () -> Void
    let onPrevious: () -> Void
    let onTogglePlayback: () -> Void
    let onNext: () -> Void
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        NowPlayingRowContent(
            session: session,
            isExpanded: isExpanded,
            topContentInset: topContentInset,
            onToggleExpanded: onToggleExpanded,
            onOpenApplication: onOpenApplication,
            onPrevious: onPrevious,
            onTogglePlayback: onTogglePlayback,
            onNext: onNext,
            onSeek: onSeek
        )
        .background {
            Button(action: onToggleExpanded) {
                Color.clear
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show or hide Now Playing details")
        }
    }
}

private struct NowPlayingRowContent: View {
    private static let artworkContainerSize: CGFloat = 38
    private static let expandedArtworkContainerSize: CGFloat = 116

    let session: NowPlayingSessionState
    let isExpanded: Bool
    let topContentInset: CGFloat?
    let onToggleExpanded: () -> Void
    let onOpenApplication: () -> Void
    let onPrevious: () -> Void
    let onTogglePlayback: () -> Void
    let onNext: () -> Void
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        NowPlayingRowLayout(isExpanded: isExpanded, topContentInset: topContentInset) {
            NowPlayingArtworkButton(
                artwork: session.artwork,
                applicationIcon: session.applicationIcon,
                applicationName: session.applicationName,
                size: isExpanded
                    ? Self.expandedArtworkContainerSize
                    : Self.artworkContainerSize,
                isExpanded: isExpanded,
                action: onOpenApplication
            )

            NowPlayingExpansionButton(
                title: session.title,
                subtitle: session.subtitle,
                showsSoundwave: isExpanded,
                action: onToggleExpanded
            )

            NowPlayingControlButton(
                symbolName: "backward.fill",
                accessibilityTitle: "Previous",
                font: .title2,
                isEnabled: session.isControllable,
                bouncesOnPress: true,
                action: onPrevious
            )
            .opacity(isExpanded ? 1 : 0)
            .allowsHitTesting(isExpanded)
            .accessibilityHidden(!isExpanded)

            NowPlayingPlaybackButton(
                isPlaying: session.isPlaying,
                font: .title,
                isEnabled: session.isControllable,
                action: onTogglePlayback
            )

            NowPlayingControlButton(
                symbolName: "forward.fill",
                accessibilityTitle: "Next",
                font: .title2,
                isEnabled: session.isControllable,
                bouncesOnPress: true,
                action: onNext
            )

            // Retain the slider through the transition. Its internal updates must
            // not inherit expansion animation; animate only its fade.
            NowPlayingProgress(session: session, isActive: isExpanded, onSeek: onSeek)
                .transaction { $0.animation = nil }
                .opacity(isExpanded ? 1 : 0)
                .allowsHitTesting(isExpanded)
                .accessibilityHidden(!isExpanded)

            NowPlayingSoundwave(
                artwork: session.artwork,
                isAnimating: isExpanded && session.isPlaying && session.playbackRate > 0.01
            )
            .frame(width: 24, height: 24)
            .scaleEffect(18.0 / 24.0)
            .frame(width: 18, height: 18)
            .opacity(isExpanded ? 1 : 0)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

// Describe endpoint geometry only. SwiftUI animates the stable subviews between
// placements; animating the Layout itself would propose intermediate sizes to
// the entire hierarchy on every frame, including the native progress slider.
private struct NowPlayingRowLayout: Layout {
    let isExpanded: Bool
    let topContentInset: CGFloat?

    struct Cache {
        var width: CGFloat = -1
        var compactTitleHeight: CGFloat = 0
        var expandedTitleHeight: CGFloat = 0
        var controlsHeight: CGFloat = 0
        var progressHeight: CGFloat = 0
    }

    func makeCache(subviews: Subviews) -> Cache { Cache() }
    func updateCache(_ cache: inout Cache, subviews: Subviews) { cache.width = -1 }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) -> CGSize {
        let width = proposal.width ?? 292
        measure(width: width, subviews: subviews, cache: &cache)
        let top = topContentInset ?? endpoint(18, 14)
        return CGSize(width: width, height: top + endpoint(38, 116) + endpoint(18, 14))
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Cache) {
        measure(width: bounds.width, subviews: subviews, cache: &cache)
        let artworkSize = endpoint(38, 116)
        let expandedWidth = max(0, bounds.width - 128)
        let compactTitleWidth = max(0, bounds.width - 114)
        let titleWidth = endpoint(compactTitleWidth, expandedWidth)
        let titleHeight = endpoint(cache.compactTitleHeight, cache.expandedTitleHeight)
        let textX = bounds.minX + endpoint(48, 128)
        let contentTop = bounds.minY + (topContentInset ?? endpoint(18, 14))
        // Keep detail-only controls anchored to the expanded top inset. The
        // compact row's extra 4 pt of padding must not move their fade-out.
        let expandedContentTop = bounds.minY + (topContentInset ?? 14)
        let stackHeight = cache.expandedTitleHeight + cache.controlsHeight + cache.progressHeight + 20
        let stackTop = (116 - stackHeight) * 0.5
        let titleY = contentTop + endpoint((38 - cache.compactTitleHeight) * 0.5, stackTop)
        let controlsY = contentTop + endpoint(
            (38 - cache.controlsHeight) * 0.5,
            stackTop + cache.expandedTitleHeight + 10
        )
        let expandedControlsY = expandedContentTop + stackTop + cache.expandedTitleHeight + 10
        subviews[0].place(at: CGPoint(x: bounds.minX, y: contentTop), anchor: .topLeading,
                          proposal: ProposedViewSize(width: artworkSize, height: artworkSize))
        subviews[1].place(at: CGPoint(x: textX, y: titleY), anchor: .topLeading,
                          proposal: ProposedViewSize(width: titleWidth, height: titleHeight))
        let controlProposal = ProposedViewSize(width: 24, height: cache.controlsHeight)
        // Expansion-only controls stay at their expanded geometry in both
        // states. They fade in place instead of travelling with play/next.
        subviews[2].place(at: CGPoint(x: bounds.minX + 140, y: expandedControlsY + cache.controlsHeight * 0.5),
                          anchor: .center, proposal: controlProposal)
        subviews[3].place(at: CGPoint(
            x: bounds.minX + endpoint(bounds.width - 44, 128 + expandedWidth * 0.5),
            y: controlsY + cache.controlsHeight * 0.5
        ), anchor: .center, proposal: controlProposal)
        subviews[4].place(at: CGPoint(x: bounds.maxX - 12, y: controlsY + cache.controlsHeight * 0.5),
                          anchor: .center, proposal: controlProposal)
        subviews[5].place(at: CGPoint(x: bounds.minX + 128, y: expandedControlsY + cache.controlsHeight + 10),
                          anchor: .topLeading,
                          proposal: ProposedViewSize(width: expandedWidth, height: cache.progressHeight))
        subviews[6].place(at: CGPoint(x: bounds.maxX - 9,
                                      y: expandedContentTop + stackTop + cache.expandedTitleHeight * 0.5 + 2),
                          anchor: .center, proposal: ProposedViewSize(width: 18, height: 18))
    }

    private func measure(width: CGFloat, subviews: Subviews, cache: inout Cache) {
        guard cache.width != width else { return }
        let expandedWidth = max(0, width - 128)
        cache.compactTitleHeight = subviews[1].sizeThatFits(
            ProposedViewSize(width: max(0, width - 114), height: nil)
        ).height
        cache.expandedTitleHeight = subviews[1].sizeThatFits(
            ProposedViewSize(width: expandedWidth, height: nil)
        ).height
        cache.controlsHeight = [2, 3, 4].map {
            subviews[$0].sizeThatFits(.unspecified).height
        }.max() ?? 24
        cache.progressHeight = subviews[5].sizeThatFits(
            ProposedViewSize(width: expandedWidth, height: nil)
        ).height
        cache.width = width
    }

    private func endpoint(_ compact: CGFloat, _ expanded: CGFloat) -> CGFloat {
        isExpanded ? expanded : compact
    }
}

private struct NowPlayingExpansionButton: View {
    private static let soundwaveReserve: CGFloat = 22

    let title: String
    let subtitle: String
    let showsSoundwave: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 2) {
                NowPlayingFadingText(title, font: .body.weight(.medium))
                if !subtitle.isEmpty {
                    NowPlayingFadingText(subtitle, font: .subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.trailing, showsSoundwave ? Self.soundwaveReserve : 0)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Show or hide Now Playing details")
    }
}

private struct NowPlayingSoundwave: View {
    private struct FallbackWaveParameter {
        let firstFrequency: Double
        let firstAmplitude: Double
        let secondFrequency: Double
        let secondAmplitude: Double
        let thirdFrequency: Double
        let thirdAmplitude: Double
        let center: Double
        let phase: Double
    }

    private static let barWidth: CGFloat = 2
    private static let fallbackParameters: [FallbackWaveParameter] = [
        .init(
            firstFrequency: 9.1, firstAmplitude: 0.20,
            secondFrequency: 13.9, secondAmplitude: 0.13,
            thirdFrequency: 19.3, thirdAmplitude: 0.08,
            center: 0.37, phase: 0
        ),
        .init(
            firstFrequency: 5.4, firstAmplitude: 0.11,
            secondFrequency: 8.4, secondAmplitude: 0.06,
            thirdFrequency: 13.1, thirdAmplitude: 0.07,
            center: 0.18, phase: 1.8
        ),
        .init(
            firstFrequency: 6.8, firstAmplitude: 0.14,
            secondFrequency: 10.5, secondAmplitude: 0.08,
            thirdFrequency: 16.7, thirdAmplitude: 0.09,
            center: 0.22, phase: 3.5
        ),
        .init(
            firstFrequency: 9.5, firstAmplitude: 0.20,
            secondFrequency: 15.1, secondAmplitude: 0.11,
            thirdFrequency: 11.3, thirdAmplitude: 0.10,
            center: 0.33, phase: 0.4
        ),
        .init(
            firstFrequency: 9.5, firstAmplitude: 0.18,
            secondFrequency: 12.3, secondAmplitude: 0.12,
            thirdFrequency: 17.9, thirdAmplitude: 0.09,
            center: 0.33, phase: 1.1
        ),
        .init(
            firstFrequency: 7.0, firstAmplitude: 0.20,
            secondFrequency: 11.2, secondAmplitude: 0.11,
            thirdFrequency: 14.3, thirdAmplitude: 0.09,
            center: 0.30, phase: 5.1
        )
    ]

    let artwork: NSImage?
    let isAnimating: Bool

    @Environment(\.displayScale) private var displayScale
    @Environment(\.colorScheme) private var colorScheme
    @State private var isVisible = false

    var body: some View {
        NowPlayingSoundwaveLayers(
            artwork: artwork,
            isAnimating: isAnimating,
            isVisible: isVisible,
            displayScale: displayScale,
            colorScheme: colorScheme
        )
        .offset(x: -1)
        .frame(width: 24, height: 24)
        .clipped()
        .onAppear { isVisible = true }
        .onDisappear { isVisible = false }
    }

    fileprivate static func bars(at date: Date) -> [CGFloat] {
        let time = date.timeIntervalSinceReferenceDate
        let sharedMovement = sin(time * 6.1) * 0.08
            + sin(time * 10.1) * 0.05

        return Self.fallbackParameters.enumerated().map { index, parameter in
            let tremorEnvelope = abs(
                sin(time * 0.7 + parameter.phase * 0.4)
            ) * abs(
                sin(time * 1.3 + parameter.phase * 0.7)
            ) * 0.13
            let tremorFrequency = 22
                + abs(sin(time * 0.3 + parameter.phase * 0.5)) * 20
            let tremor = sin(
                time * tremorFrequency + parameter.phase * 2.1
            ) * tremorEnvelope
            let rawLevel = parameter.center
                + sin(time * parameter.firstFrequency + parameter.phase)
                    * parameter.firstAmplitude
                + sin(time * parameter.secondFrequency + parameter.phase * 1.3)
                    * parameter.secondAmplitude
                + sin(time * parameter.thirdFrequency + parameter.phase * 0.9)
                    * parameter.thirdAmplitude
                + tremor
                + sharedMovement
            let ceiling = index == 3 || index == 4 ? 0.83 : 0.96
            let level = max(0.04, min(ceiling, rawLevel))

            return Self.barWidth + CGFloat(level) * 22
        }
    }
}

// Keep the continuously changing visual out of SwiftUI's attribute graph.
// SwiftUI supplies artwork/playback/visibility; the six tiny layers own drawing.
private struct NowPlayingSoundwaveLayers: NSViewRepresentable {
    let artwork: NSImage?
    let isAnimating: Bool
    let isVisible: Bool
    let displayScale: CGFloat
    let colorScheme: ColorScheme

    func makeNSView(context: Context) -> NowPlayingSoundwaveLayerView {
        NowPlayingSoundwaveLayerView(frame: CGRect(x: 0, y: 0, width: 24, height: 24))
    }

    func updateNSView(_ view: NowPlayingSoundwaveLayerView, context: Context) {
        view.configure(
            artwork: artwork, isAnimating: isAnimating, isVisible: isVisible,
            displayScale: displayScale, colorScheme: colorScheme
        )
    }

    static func dismantleNSView(_ view: NowPlayingSoundwaveLayerView, coordinator: ()) {
        view.stop()
    }
}

private final class NowPlayingSoundwaveLayerView: NSView {
    private let textureLayer = CALayer()
    private let maskLayer = CALayer()
    private var barLayers: [CAShapeLayer] = []
    private var timer: Timer?
    private var heights = Array(repeating: CGFloat(2), count: 6)
    private var velocities = Array(repeating: CGFloat.zero, count: 6)
    private var lastTick = CACurrentMediaTime()
    private var isAnimating = false
    private var isVisible = false
    private var artworkID: ObjectIdentifier?
    private var renderedScale: CGFloat = 0
    private var renderedScheme: ColorScheme?
    private var windowObservers: [NSObjectProtocol] = []

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        textureLayer.frame = CGRect(x: 0, y: 0, width: 24, height: 24)
        maskLayer.frame = textureLayer.bounds
        textureLayer.mask = maskLayer
        layer?.addSublayer(textureLayer)
        for index in 0..<6 {
            let bar = CAShapeLayer()
            bar.frame = CGRect(x: 12 - 8.75 + CGFloat(index) * 3.5 - 1, y: 0, width: 2, height: 24)
            bar.fillColor = NSColor.white.cgColor
            bar.path = Self.path(height: 2)
            maskLayer.addSublayer(bar)
            barLayers.append(bar)
        }
    }

    required init?(coder: NSCoder) { nil }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
        windowObservers.removeAll()
        if window == nil {
            stop()
        } else if let window {
            // MenuBarExtra may hide and reuse the same window without removing
            // this view. Resume when that window becomes key again.
            windowObservers = [
                NotificationCenter.default.addObserver(
                    forName: NSWindow.didBecomeKeyNotification, object: window, queue: .main
                ) { [weak self] _ in
                    guard let self, self.isVisible, self.isAnimating else { return }
                    self.start()
                },
                NotificationCenter.default.addObserver(
                    forName: NSWindow.didResignKeyNotification, object: window, queue: .main
                ) { [weak self] _ in self?.stop() }
            ]
            if isVisible && isAnimating { start() }
        }
    }

    deinit {
        timer?.invalidate()
        for observer in windowObservers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    func configure(
        artwork: NSImage?, isAnimating: Bool, isVisible: Bool,
        displayScale: CGFloat, colorScheme: ColorScheme
    ) {
        let nextID = artwork.map(ObjectIdentifier.init)
        if nextID != artworkID || displayScale != renderedScale || colorScheme != renderedScheme {
            // Render the exact existing filtered fill once per artwork/appearance,
            // rather than re-evaluating its image, blur and blend every frame.
            let renderer = ImageRenderer(content:
                NowPlayingSoundwaveFill(artwork: artwork, fallbackColor: .secondary)
                    .frame(width: 24, height: 24)
                    .environment(\.colorScheme, colorScheme)
            )
            renderer.scale = displayScale
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            textureLayer.contents = renderer.cgImage
            textureLayer.contentsScale = displayScale
            CATransaction.commit()
            artworkID = nextID
            renderedScale = displayScale
            renderedScheme = colorScheme
        }
        self.isAnimating = isAnimating
        self.isVisible = isVisible
        if !isVisible {
            stop()
        } else if isAnimating || heights.contains(where: { abs($0 - 2) > 0.01 }) {
            start()
        }
    }

    private func start() {
        guard timer == nil, window != nil else { return }
        lastTick = CACurrentMediaTime()
        let timer = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            self?.tick()
        }
        timer.tolerance = 0.002
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        heights = Array(repeating: 2, count: 6)
        velocities = Array(repeating: 0, count: 6)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for bar in barLayers {
            bar.removeAllAnimations()
            bar.path = Self.path(height: 2)
        }
        CATransaction.commit()
    }

    private func tick() {
        guard isVisible, window?.isVisible == true else {
            // A closed menu-bar window can retain its SwiftUI content.
            stop()
            return
        }
        let now = CACurrentMediaTime()
        let delta = min(max(now - lastTick, 0), 0.1)
        lastTick = now
        let targets = isAnimating
            ? NowPlayingSoundwave.bars(at: Date())
            : Array(repeating: CGFloat(2), count: 6)
        let response = isAnimating ? 0.18 : 0.42
        let damping = isAnimating ? 0.65 : 0.82
        let omega = 2 * Double.pi / response
        let decay = damping * omega
        let frequency = omega * sqrt(1 - damping * damping)
        let envelope = exp(-decay * delta)
        let cosine = cos(frequency * delta)
        let sine = sin(frequency * delta)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        for index in 0..<6 {
            // Analytic damped spring step, including velocity between targets.
            // The response/damping and 30 Hz target waveform match the old view.
            let displacement = Double(heights[index] - targets[index])
            let velocity = Double(velocities[index])
            let coefficient = (velocity + decay * displacement) / frequency
            let nextDisplacement = envelope * (displacement * cosine + coefficient * sine)
            heights[index] = targets[index] + CGFloat(nextDisplacement)
            velocities[index] = CGFloat(envelope * (
                -decay * (displacement * cosine + coefficient * sine)
                + frequency * (-displacement * sine + coefficient * cosine)
            ))
            let bar = barLayers[index]
            let nextPath = Self.path(height: heights[index])
            let animation = CABasicAnimation(keyPath: "path")
            animation.fromValue = bar.presentation()?.path ?? bar.path
            animation.toValue = nextPath
            animation.duration = 1.0 / 30.0
            animation.timingFunction = CAMediaTimingFunction(name: .linear)
            bar.path = nextPath
            bar.add(animation, forKey: "height")
        }
        CATransaction.commit()
        if !isAnimating && zip(heights, velocities).allSatisfy({ abs($0.0 - 2) < 0.01 && abs($0.1) < 0.05 }) {
            stop()
        }
    }

    private static func path(height: CGFloat) -> CGPath {
        let height = max(0, height)
        return CGPath(
            roundedRect: CGRect(x: 0, y: 12 - height * 0.5, width: 2, height: height),
            cornerWidth: min(2, height) * 0.5,
            cornerHeight: min(2, height) * 0.5,
            transform: nil
        )
    }
}

private struct NowPlayingSoundwaveFill: View {
    let artwork: NSImage?
    let fallbackColor: Color

    var body: some View {
        if let artwork {
            Image(nsImage: artwork)
                .resizable()
                .aspectRatio(contentMode: .fill)
                .frame(width: 24, height: 24)
                .clipped()
                .saturation(1.25)
                .blur(radius: 5)
                .overlay {
                    Rectangle()
                        .fill(Color(white: 0.12))
                        .blendMode(.screen)
                }
        } else {
            LinearGradient(
                colors: [fallbackColor, fallbackColor],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }
}

private struct NowPlayingFadingText: View {
    private static let fadeWidth: CGFloat = 24

    let text: String
    let font: Font

    init(_ text: String, font: Font) {
        self.text = text
        self.font = font
    }

    var body: some View {
        Text(verbatim: " ")
            .font(font)
            .lineLimit(1)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .leading) {
                Text(verbatim: text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
            }
            .mask {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(.white)

                    LinearGradient(
                        colors: [.white, .clear],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: Self.fadeWidth)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(verbatim: text))
    }
}

private struct NowPlayingArtworkButton: View {
    let artwork: NSImage?
    let applicationIcon: NSImage?
    let applicationName: String
    let size: CGFloat
    let isExpanded: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .bottomTrailing) {
                NowPlayingArtwork(
                    artwork: artwork,
                    size: size,
                    isExpanded: isExpanded
                )

                if let applicationIcon {
                    Image(nsImage: applicationIcon)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 20, height: 20)
                        .shadow(
                            color: .black.opacity(0.24),
                            radius: 4,
                            y: 2
                        )
                        .offset(x: 3, y: 3)
                }
            }
            .frame(width: size, height: size)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(
            applicationName.isEmpty
                ? "Open media application"
                : "Open \(applicationName)"
        )
    }
}

private struct NowPlayingArtwork: View {
    let artwork: NSImage?
    let size: CGFloat
    let isExpanded: Bool

    var body: some View {
        let cornerRadius = renderedArtworkCornerRadius

        ZStack(alignment: .leading) {
            Color.clear

            if let artwork {
                Image(nsImage: artwork)
                    .resizable()
                    .interpolation(.high)
                    .antialiased(true)
                    .scaledToFit()
                    .clipShape(
                        RoundedRectangle(
                            cornerRadius: cornerRadius,
                            style: .continuous
                        )
                    )
                    .shadow(
                        color: .black.opacity(0.2),
                        radius: 6,
                        y: 3
                    )
            } else {
                Image(systemName: "music.note")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                    .frame(
                        maxWidth: .infinity,
                        maxHeight: .infinity,
                        alignment: .center
                    )
            }
        }
        .frame(width: size, height: size, alignment: .leading)
    }

    private var renderedArtworkCornerRadius: CGFloat {
        guard let artwork,
              artwork.size.width > 0,
              artwork.size.height > 0 else {
            return isExpanded ? min(8, size * 0.1) : 10
        }

        let scale = min(
            size / artwork.size.width,
            size / artwork.size.height
        )
        let renderedShortestEdge = min(
            artwork.size.width * scale,
            artwork.size.height * scale
        )
        let aspectRatio = max(artwork.size.width, artwork.size.height)
            / min(artwork.size.width, artwork.size.height)
        let isApproximatelySquare = aspectRatio <= 1.05
        if isApproximatelySquare {
            return isExpanded
                ? min(8, renderedShortestEdge * 0.1)
                : 10
        }
        return renderedShortestEdge * 0.1
    }
}

private struct NowPlayingControlButton: View {
    @State private var bounceTrigger = 0

    let symbolName: String
    let accessibilityTitle: LocalizedStringResource
    let font: Font
    let isEnabled: Bool
    let bouncesOnPress: Bool
    let action: () -> Void

    var body: some View {
        Button {
            if bouncesOnPress {
                bounceTrigger &+= 1
            }
            action()
        } label: {
            Image(systemName: symbolName)
                .font(font)
                .symbolEffect(.bounce, value: bounceTrigger)
                .frame(minWidth: 24, minHeight: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .foregroundStyle(isEnabled ? .secondary : .primary)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(accessibilityTitle)
    }
}

private struct NowPlayingPlaybackButton: View {
    let isPlaying: Bool
    let font: Font
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: isPlaying ? "pause.fill" : "play.fill")
                .font(font)
                .contentTransition(.symbolEffect(.replace.downUp))
                .animation(.default, value: isPlaying)
                // Let an in-flight replace travel with the expansion animation
                // instead of jumping to the new position.
                .geometryGroup()
                .frame(minWidth: 24, minHeight: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(NowPlayingPressHighlightStyle())
        .disabled(!isEnabled)
        .opacity(isEnabled ? 1 : 0.35)
        .accessibilityLabel(isPlaying ? "Pause" : "Play")
    }
}

/// Brightens the symbol while pressed, like the system Now Playing controls.
private struct NowPlayingPressHighlightStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .foregroundStyle(!isEnabled || configuration.isPressed ? .primary : .secondary)
    }
}

private struct NowPlayingProgress: View {
    @State private var isSeeking = false
    @State private var seekPosition: TimeInterval = 0

    let session: NowPlayingSessionState
    let isActive: Bool
    let onSeek: (TimeInterval) -> Void

    var body: some View {
        TimelineView(.animation(minimumInterval: 1, paused: !isActive || !session.isPlaying)) { context in
            let elapsed = session.elapsedTime(at: context.date)
            let duration = max(session.duration ?? 0, 0)
            let canSeek = session.isControllable && duration > 0
            let displayedElapsed = isSeeking ? seekPosition : elapsed

            VStack(spacing: 3) {
                Slider(
                    value: Binding(
                        get: {
                            isSeeking ? seekPosition : elapsed
                        },
                        set: { nextPosition in
                            seekPosition = min(
                                max(0, nextPosition),
                                duration
                            )
                        }
                    ),
                    in: 0...max(duration, 1),
                    onEditingChanged: { isEditing in
                        if isEditing {
                            seekPosition = elapsed
                            isSeeking = true
                        } else {
                            onSeek(seekPosition)
                            isSeeking = false
                        }
                    }
                )
                .controlSize(.small)
                .disabled(!canSeek)

                HStack {
                    Text(
                        Duration.seconds(displayedElapsed),
                        format: .time(pattern: .minuteSecond)
                    )
                        .monospacedDigit()
                    Spacer()
                    Text(
                        verbatim: "−\(Duration.seconds(max(duration - displayedElapsed, 0)).formatted(.time(pattern: .minuteSecond)))"
                    )
                    .monospacedDigit()
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
    }
}
