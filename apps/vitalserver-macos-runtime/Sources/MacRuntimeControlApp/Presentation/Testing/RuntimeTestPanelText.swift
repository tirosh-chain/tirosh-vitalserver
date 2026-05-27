enum RuntimeTestPanelText {
    static let summary = "Test"
    static let description = "Development and verification tools for exercising VitalServer with virtual recorders."
    static let browserChecks = "Browser"
    static let runtimeControlConsole = "Runtime Control console"
    static let runtimeControlConsoleHelp = "Opens the local browser console for Runtime Control API status, event streams, and log streams."
    static let testkitService = "TestKit virtual recorders"
    static let testKitUnavailable = "TestKit is unavailable for this build."
    static let noActiveSession = "No active TestKit session."
    static let startingSession = "Starting virtual VRecorder..."
    static let stoppingSession = "Stopping virtual VRecorder..."
    static let deletingSession = "Deleting virtual VRecorder session..."
    static let resettingSessions = "Resetting virtual VRecorder sessions..."
    static let refreshedStatus = "Refreshed TestKit status."
    static let sharedContainerIPWarning = """
    Multiple virtual VRecorders in one TestKit container share the same source IP. Use this for traffic/load checks; use one container per VRecorder when IP uniqueness or Network Settings redirection must be tested.
    """

    static func startedSession(_ id: String) -> String {
        "Started TestKit session \(id)."
    }

    static func stoppedSession(_ id: String) -> String {
        "Stopped TestKit session \(id)."
    }

    static func deletedSession(_ id: String) -> String {
        "Deleted TestKit session \(id)."
    }

    static func resetSessions(_ count: Int) -> String {
        "Reset \(count) TestKit sessions."
    }
}
