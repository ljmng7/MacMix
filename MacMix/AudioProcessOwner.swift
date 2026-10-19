import Darwin

/// Finds the regular application that owns a HAL audio process.
///
/// WKWebView media in third-party apps, including iPad apps on the Mac, plays
/// from a `com.apple.WebKit.GPU` XPC service whose parent is launchd. Only the
/// kernel's responsibility link points back at the hosting app, so it is
/// checked before walking parents.
nonisolated enum AudioProcessOwner {
    static func resolve(
        pid: pid_t,
        isRegularApp: (pid_t) -> Bool,
        responsiblePID: (pid_t) -> pid_t?,
        parentPID: (pid_t) -> pid_t?
    ) -> pid_t? {
        if isRegularApp(pid) {
            return pid
        }
        if let responsible = responsiblePID(pid), responsible != pid, isRegularApp(responsible) {
            return responsible
        }

        var visited: Set<pid_t> = [pid]
        var currentPID = pid
        while let parent = parentPID(currentPID), parent > 0, !visited.contains(parent) {
            if isRegularApp(parent) {
                return parent
            }
            visited.insert(parent)
            currentPID = parent
        }
        return nil
    }

    private typealias ResponsiblePIDFunction = @convention(c) (pid_t) -> pid_t

    // libsystem export used by Activity Monitor; absent symbols fall back to parents.
    private static let responsiblePIDFunction: ResponsiblePIDFunction? = {
        let defaultHandle = UnsafeMutableRawPointer(bitPattern: -2)
        guard let symbol = dlsym(defaultHandle, "responsibility_get_pid_responsible_for_pid") else {
            return nil
        }
        return unsafeBitCast(symbol, to: ResponsiblePIDFunction.self)
    }()

    static func responsiblePID(for pid: pid_t) -> pid_t? {
        guard let function = responsiblePIDFunction else {
            return nil
        }
        let responsible = function(pid)
        return responsible > 0 ? responsible : nil
    }
}
