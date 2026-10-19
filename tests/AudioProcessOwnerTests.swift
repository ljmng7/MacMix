import Darwin

// Process table: 1 launchd, 100 Music, 200 Chrome, 201 Chrome helper,
// 509 Lumo (iPad app), 513 Lumo's WebKit GPU service, 700 audio daemon.
let regularApps: Set<pid_t> = [100, 200, 509]
let parents: [pid_t: pid_t] = [100: 1, 200: 1, 201: 200, 509: 1, 513: 1, 700: 1]
let responsible: [pid_t: pid_t] = [100: 100, 201: 200, 509: 509, 513: 509, 700: 700]

func owner(_ pid: pid_t, responsibleTable: [pid_t: pid_t] = responsible,
           parentTable: [pid_t: pid_t] = parents) -> pid_t? {
    AudioProcessOwner.resolve(pid: pid, isRegularApp: { regularApps.contains($0) },
        responsiblePID: { responsibleTable[$0] }, parentPID: { parentTable[$0] })
}

@main struct AudioProcessOwnerTests {
    static func main() {
        precondition(owner(100) == 100, "a regular app owns its own audio")
        precondition(owner(513) == 509, "WebKit GPU audio of an iPad app belongs to the app")
        precondition(owner(201) == 200, "helper processes resolve to their app")
        precondition(owner(201, responsibleTable: [:]) == 200, "parent walk still works without responsibility")
        precondition(owner(513, responsibleTable: [:]) == nil, "launchd-owned service without responsibility stays unowned")
        precondition(owner(700) == nil, "a self-responsible daemon is never an app row")
        precondition(owner(5, responsibleTable: [:], parentTable: [5: 6, 6: 5]) == nil, "parent cycles terminate")
        precondition(AudioProcessOwner.responsiblePID(for: getpid()) != nil, "libsystem responsibility lookup is available")
        print("Audio process owner: app, WebKit GPU service, helpers, daemons, parent cycles and live responsibility lookup passed.")
    }
}
