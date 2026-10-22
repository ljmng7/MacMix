import Foundation

/// Native tracking remains immediate; model/DSP work consumes only the newest
/// edit per interval. Common run-loop modes keep delivery alive during mouse tracking.
@MainActor
public final class EqualizerEditCoalescer {
    private let interval: TimeInterval
    private var timer: Timer?
    private var pending: (@MainActor () -> Void)?

    public init(interval: TimeInterval = 0.016) { self.interval = interval }
    public func submit(_ action: @escaping @MainActor () -> Void) {
        pending = action
        guard timer == nil else { return }
        let timer = Timer(timeInterval: interval, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.flush() }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }
    public func flush() {
        timer?.invalidate()
        timer = nil
        let action = pending
        pending = nil
        action?()
    }
    public func cancel() {
        timer?.invalidate()
        timer = nil
        pending = nil
    }
    deinit { timer?.invalidate() }
}
