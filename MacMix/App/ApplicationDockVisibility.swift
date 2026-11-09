import AppKit

/// SwiftUI retains Window content after its NSWindow closes, so onDisappear
/// alone cannot restore a menu-bar app's accessory activation policy.
@MainActor
final class ApplicationDockVisibility {
    static let shared = ApplicationDockVisibility()

    private let windows = NSHashTable<NSWindow>.weakObjects()
    private var observers: [NSObjectProtocol] = []
    private var closingWindows: Set<ObjectIdentifier> = []
    private let showsMenuBarItem: () -> Bool

    init(showsMenuBarItem: @escaping () -> Bool = {
        UserDefaults.standard.object(forKey: "MacMix.ShowsMenuBarItem") as? Bool ?? true
    }) {
        self.showsMenuBarItem = showsMenuBarItem
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: NSWindow.willCloseNotification,
            object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let window = notification.object as? NSWindow,
                      self.windows.contains(window) else { return }
                // willClose arrives while isVisible is still true, and SwiftUI
                // runs onDisappear (which calls refresh()) inside the same
                // close. Treat the window as closed until the close finishes,
                // or that refresh briefly restores the Dock icon.
                let id = ObjectIdentifier(window)
                self.closingWindows.insert(id)
                self.refresh()
                // Reconcile once the close has finished; a later reopen is
                // determined by the real window visibility, not a stale flag.
                DispatchQueue.main.async { [weak self] in
                    self?.closingWindows.remove(id)
                    self?.refresh()
                }
            }
        })
        observers.append(center.addObserver(forName: NSWindow.didBecomeKeyNotification,
            object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let self, let window = notification.object as? NSWindow,
                      self.windows.contains(window) else { return }
                self.refresh()
            }
        })
    }

    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
    }

    func track(_ window: NSWindow) {
        windows.add(window)
        if window.isVisible || window.isMiniaturized {
            refresh()
        }
    }

    func refresh() {
        let hasOpenWindow = windows.allObjects.contains {
            !closingWindows.contains(ObjectIdentifier($0)) && ($0.isVisible || $0.isMiniaturized)
        }
        let policy: NSApplication.ActivationPolicy = showsMenuBarItem() && !hasOpenWindow
            ? .accessory : .regular
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
    }
}
