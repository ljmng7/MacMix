import SwiftUI

struct DiagnosticAboutSection: View {
    @Environment(\.openWindow) private var openWindow
    @State private var confirmsClear = false
    @State private var labelHeight: CGFloat = 0
    private let model = DiagnosticFeedbackModel.shared

    var body: some View {
        Section {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Logs and Feedback")
                    Text("Storage Used: \(storageDescription)")
                        .font(.caption).foregroundStyle(.secondary)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { labelHeight = $0 }
                Spacer(minLength: 12)
                // The sizing button keeps the native row's original height.
                // Its centered overlay grows only into the existing row padding.
                feedbackButton(fillsHeight: false)
                    .hidden()
                    .overlay(alignment: .center) {
                        feedbackButton(fillsHeight: true)
                            .frame(height: labelHeight > 0 ? labelHeight + 4 : nil)
                            .disabled(model.isWorking)
                    }
            }
            HStack(spacing: 12) {
                Button("Show in Finder") { Task { await model.showLogsInFinder() } }
                Spacer()
                Button("Clear Logs", role: .destructive) { confirmsClear = true }
            }
            .buttonStyle(.bordered)
            .tint(nil)
            .foregroundStyle(.primary)
            .disabled(model.isWorking)
        } header: {
            Text("Feedback")
        } footer: {
            Text("Logs and diagnostic recordings stay on this Mac for up to 7 days and contain no audio, media titles or license information.")
        }
        .modifier(DiagnosticClearLogsConfirmation(isPresented: $confirmsClear, model: model))
        .task {
            while !Task.isCancelled {
                await model.refreshStorageUsage()
                do { try await Task.sleep(for: .seconds(2)) } catch { return }
            }
        }
    }

    private var storageDescription: String {
        model.storageBytes.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) } ?? "—"
    }

    private func feedbackButton(fillsHeight: Bool) -> some View {
        Button { openWindow(id: DiagnosticFeedbackView.windowID) } label: {
            Label("Feedback", systemImage: "exclamationmark.bubble")
                .frame(maxHeight: fillsHeight ? .infinity : nil)
        }
        .buttonStyle(.bordered)
        .buttonBorderShape(.capsule)
        .tint(nil)
        .foregroundStyle(.primary)
    }
}

struct DiagnosticClearLogsConfirmation: ViewModifier {
    @Binding var isPresented: Bool
    let model: DiagnosticFeedbackModel

    func body(content: Content) -> some View {
        content.alert("Clear All Logs?", isPresented: $isPresented) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) {
                Task { await model.clear() }
            }
        } message: {
            if model.startedAt != nil {
                Text("This stops the current recording and deletes all logs and saved diagnostic recordings.")
            } else {
                Text("This deletes all logs and saved diagnostic recordings. New events will continue to be logged.")
            }
        }
    }
}
