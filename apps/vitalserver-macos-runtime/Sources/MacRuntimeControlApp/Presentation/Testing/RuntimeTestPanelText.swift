enum RuntimeTestPanelText {
    static let summary = "Test"
    static let description = "Development and verification tools for exercising VitalServer with virtual recorders."
    static let browserChecks = "Browser"
    static let runtimeControlConsole = "Runtime Control console"
    static let runtimeControlConsoleHelp = "Opens the local browser console for Runtime Control API status, event streams, and log streams."
    static let testkitService = "TestKit virtual recorders"
    static let testKitUnavailable = "TestKit is unavailable for this build."
    static let noActiveSession = "No active TestKit session."

    static func startedSession(_ id: String) -> String {
        "Started TestKit session \(id)."
    }

    static func stoppedSession(_ id: String) -> String {
        "Stopped TestKit session \(id)."
    }
}
