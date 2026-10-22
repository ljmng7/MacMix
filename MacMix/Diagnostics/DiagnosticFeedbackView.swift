import AppKit
import SwiftUI

/// Shown in its own window so the main window stays usable while recording.
struct DiagnosticFeedbackView: View {
    static let windowID = "feedback"
    let model: DiagnosticFeedbackModel
    @AppStorage("MacMix.Feedback.IncludesRecentLogs") private var includesRecentLogs = true
    @State private var selectedIdentificationIDs: Set<String> = []
    /// Height of the recording row's text; buttons span it like the About page.
    @State private var rowLabelHeight: CGFloat = 0
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            Form {
                recordingSection
                attachmentSection
            }
            .formStyle(.grouped)
            footer
        }
        .frame(width: 500, height: 570)
        .onAppear { model.refreshIdentificationCandidates() }
    }

    // MARK: Recording

    private var recordingSection: some View {
        Section {
            if let started = model.startedAt {
                RecordingRow(labelHeight: $rowLabelHeight) {
                    Text("Recording")
                    RecordingElapsedText(startedAt: started, markerCount: model.markerCount)
                } buttons: { height in
                    RowCapsuleButton(height: height, action: model.markProblem) {
                        Label("Problem Happened", systemImage: "flag")
                    }
                    .help(Text("Mark the moment the problem occurs"))
                    RowCapsuleButton(height: height, foreground: .red, action: { Task { await model.stop() } }) {
                        Label("Stop", systemImage: "stop.fill")
                    }
                }
            } else if model.isSavingRecording {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Saving recording…").foregroundStyle(.secondary)
                }
            } else if let recording = model.recording {
                RecordingRow(labelHeight: $rowLabelHeight) {
                        Text(recording.url.lastPathComponent)
                            .lineLimit(1)
                            .truncationMode(.middle)
                        HStack(spacing: 4) {
                            Text(Duration.seconds(recording.duration).formatted(.time(pattern: .minuteSecond)))
                                .monospacedDigit()
                            if recording.markerCount > 0 {
                                Text(verbatim: "·")
                                Label { Text(recording.markerCount, format: .number) } icon: { Image(systemName: "flag.fill") }
                            }
                            Text(verbatim: "·")
                            Text("Attached")
                        }
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } buttons: { height in
                    RowCapsuleButton(height: height, action: {
                        NSWorkspace.shared.activateFileViewerSelecting([recording.url])
                    }) {
                        Image(systemName: "magnifyingglass")
                    }
                    .help(Text("Show in Finder"))
                    RowCapsuleButton(height: height, action: model.discardRecording) {
                        Text("Cancel")
                    }
                    .help(Text("Delete this recording"))
                }
            } else {
                RecordingRow(labelHeight: $rowLabelHeight) {
                    Text("Record the Problem")
                    Text("Start, reproduce the issue, then stop. Up to 5 minutes.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } buttons: { height in
                    RowCapsuleButton(height: height, foreground: .green, action: model.start) {
                        Label("Start", systemImage: "record.circle")
                    }
                }
            }
        } header: {
            // Part of the form so it scrolls with the content instead of staying pinned.
            VStack(alignment: .leading, spacing: 0) {
                FeedbackHeader()
                Text("Diagnostic Recording")
            }
        }
    }

    // MARK: Attachments

    private var attachmentSection: some View {
        // Read in the body so the list follows the panel's devices and apps live.
        let items = model.affectedItems()
        return Section {
            HStack {
                Toggle("Recent Logs", isOn: $includesRecentLogs)
                    .toggleStyle(.checkbox)
                Spacer()
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Affected Devices and Apps")
                if items.isEmpty {
                    Text("No audio devices or apps right now.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                ForEach(items) { item in
                    Toggle(isOn: selection(for: item.id)) {
                        AffectedItemLabel(item: item)
                    }
                    .toggleStyle(.checkbox)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } header: {
            Text("Include in Email")
        } footer: {
            Text("Logs contain no audio, media titles or license information.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        // Keep items that disappear after selection, e.g. a device that dropped out.
        .onChange(of: items.map(\.id)) { model.refreshIdentificationCandidates() }
    }

    private func selection(for id: String) -> Binding<Bool> {
        Binding(get: { selectedIdentificationIDs.contains(id) }, set: { included in
            if included { selectedIdentificationIDs.insert(id) } else { selectedIdentificationIDs.remove(id) }
        })
    }

    // MARK: Footer

    private var footer: some View {
        VStack(alignment: .trailing, spacing: 10) {
            if let message = model.message {
                Text(message)
                    .font(.callout)
                    .foregroundStyle(model.failed ? Color.red : Color.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack(spacing: 10) {
                Spacer()
                if model.isWorking { ProgressView().controlSize(.small) }
                SendFeedbackButton(height: rowLabelHeight > 0 ? rowLabelHeight + 4 : nil) {
                    Task {
                        let opened = await model.composeEmail(includeRecentLogs: includesRecentLogs,
                            selectedIdentificationIDs: selectedIdentificationIDs,
                            prompt: String(localized: "Describe what happened and how to reproduce it:"))
                        if opened { dismiss() }
                    }
                }
                .disabled(model.isSavingRecording)
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 20)
        .padding(.top, 4)
        .disabled(model.isWorking)
    }
}

/// A two-line row whose trailing buttons fill the text height, as on the About
/// page: hidden sizing copies keep the native row height and the visible
/// buttons grow only into the row's existing padding.
private struct RecordingRow<Label: View, Buttons: View>: View {
    @Binding var labelHeight: CGFloat
    @ViewBuilder let label: () -> Label
    @ViewBuilder let buttons: (_ height: CGFloat?) -> Buttons

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) { label() }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { labelHeight = $0 }
            Spacer(minLength: 12)
            HStack(spacing: 8) { buttons(nil) }
                .hidden()
                .overlay(alignment: .trailing) {
                    HStack(spacing: 8) { buttons(labelHeight > 0 ? labelHeight + 4 : nil) }
                        .fixedSize()
                }
        }
    }
}

/// Matches the About page's Feedback button: glass capsule on macOS 26,
/// bordered capsule otherwise, both controlled by `usesLiquidGlass`.
private struct RowCapsuleButton<Content: View>: View {
    var height: CGFloat?
    var foreground: Color?
    let action: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        let style = foreground.map(AnyShapeStyle.init) ?? AnyShapeStyle(.primary)
        let button = Button(action: action) {
            content().frame(maxHeight: height == nil ? nil : .infinity)
        }
        .frame(height: height)
        .buttonBorderShape(.capsule)
        .tint(nil)
        .foregroundStyle(style)
        if #available(macOS 26.0, *), AppAppearanceFeatures.usesLiquidGlass {
            button.buttonStyle(.glass)
        } else {
            button.buttonStyle(.bordered)
        }
    }
}

private struct SendFeedbackButton: View {
    var height: CGFloat?
    let action: () -> Void
    @AppStorage(ThemePreference.accentColor) private var accentColor: ThemeAccentColor = .system
    @Environment(\.hasStudioAccess) private var hasStudioAccess

    var body: some View {
        let tint = accentColor.resolvedColor(hasStudioAccess: hasStudioAccess)
        let button = Button(action: action) {
            Label("Send", systemImage: "envelope.fill")
                .padding(.horizontal, 4)
                .frame(maxHeight: height == nil ? nil : .infinity)
        }
        .frame(height: height)
        .keyboardShortcut(.defaultAction)
        .buttonBorderShape(.capsule)
        .tint(tint)
        if #available(macOS 26.0, *), AppAppearanceFeatures.usesLiquidGlass {
            button.buttonStyle(.glassProminent)
        } else {
            button
                .buttonStyle(.borderedProminent)
                .shadow(color: tint.opacity(0.35), radius: 6, y: 2)
        }
    }
}

/// Same header the feedback sheet had before it moved to its own window.
private struct FeedbackHeader: View {
    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "envelope.fill")
                .font(.title2)
                .foregroundStyle(.white)
                .frame(width: 40, height: 40)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text("Send Feedback").font(.title2.bold())
                    .foregroundStyle(.primary)
                Text("Write to the developer by email.")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.bottom, 28)
    }
}

private struct RecordingElapsedText: View {
    let startedAt: Date
    let markerCount: Int

    var body: some View {
        TimelineView(.periodic(from: startedAt, by: 1)) { context in
            let elapsed = min(DiagnosticSamplingPolicy.maximumDuration, max(0, context.date.timeIntervalSince(startedAt)))
            HStack(spacing: 4) {
                Text(Duration.seconds(elapsed).formatted(.time(pattern: .minuteSecond)))
                    .monospacedDigit()
                if markerCount > 0 {
                    Text(verbatim: "·")
                    Label { Text(markerCount, format: .number) } icon: { Image(systemName: "flag.fill") }
                        .help(Text("Problem markers"))
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

private struct AffectedItemLabel: View {
    let item: FeedbackAffectedItem

    var body: some View {
        HStack(spacing: 8) {
            switch item.icon {
            case let .device(symbolName, systemIcon, isCurrent):
                DeviceIcon(symbolName: symbolName, systemIcon: systemIcon, isCurrent: isCurrent, showsBackground: false)
            case let .application(image, isMuted):
                AppIcon(image: image, isMuted: isMuted)
                    .frame(width: 26, height: 26)
            }
            Text(item.candidate.displayName)
                .lineLimit(1)
        }
    }
}
