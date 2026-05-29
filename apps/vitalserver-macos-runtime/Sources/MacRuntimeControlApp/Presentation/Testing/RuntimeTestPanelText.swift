enum RuntimeTestPanelText {
    static let summary = "Test"
    static let description = "Development and verification tools for exercising VitalServer with virtual recorders."
    static let browserChecks = "Browser"
    static let runtimeControlConsole = "Remote Console"
    static let runtimeControlConsoleHelp = "Opens the Remote Console for Runtime Control API status, event streams, and log streams."
    static let testkitService = "TestKit virtual recorders"
    static let testKitUnavailable = "TestKit is unavailable for this build."
    static let noActiveSession = "No active TestKit session."
    static let noBeds = "Create beds before starting virtual VRecorders."
    static let chooseBeds = "Select available beds, then start virtual VRecorders against those beds."
    static let activeBed = "In use"
    static let activeBedHelp = "This bed is assigned to an active TestKit session."
    static let creatingBeds = "Creating TestKit beds..."
    static let stopSessionsBeforeDeletingBed = "Stop or delete active TestKit sessions before deleting this bed."
    static let resettingBeds = "Resetting TestKit beds..."
    static let startingSession = "Starting virtual VRecorder..."
    static let pausingSession = "Pausing virtual VRecorder..."
    static let resumingSession = "Resuming virtual VRecorder..."
    static let stoppingSession = "Stopping virtual VRecorder..."
    static let restartingSession = "Restarting virtual VRecorder..."
    static let deletingSession = "Deleting virtual VRecorder session..."
    static let resettingSessions = "Resetting virtual VRecorder sessions..."
    static let refreshedStatus = "Refreshed TestKit status."
    static let orphanCleanup = "Orphan cleanup"
    static let orphanCleanupDescription = "Delete a VRecorder that remains in VitalServer even when no TestKit session is available."
    static let missingVrcode = "Enter a VRecorder code to delete."
    static let stopSessionsBeforeResettingBeds = "Stop or delete active TestKit sessions before resetting beds."
    static let sharedContainerIPWarning = """
    Multiple virtual VRecorders in one TestKit container share the same source IP. Use this for traffic/load checks; use one container per VRecorder when IP uniqueness or Network Settings redirection must be tested.
    """

    static func createdBeds(_ count: Int) -> String {
        "Registered \(count) TestKit beds."
    }

    static func resetBeds(_ count: Int) -> String {
        "Reset \(count) TestKit beds."
    }

    static func deletingBed(_ roomName: String) -> String {
        "Deleting TestKit bed \(roomName)..."
    }

    static func deletedBed(_ roomName: String) -> String {
        "Deleted TestKit bed \(roomName)."
    }

    static func insufficientBeds(_ bedCount: Int, _ recorderCount: Int) -> String {
        "Create at least \(recorderCount) beds before starting \(recorderCount) VRecorders. Current beds: \(bedCount)."
    }

    static func insufficientSelectedBeds(_ selectedBedCount: Int, _ recorderCount: Int) -> String {
        "Select at least \(recorderCount) available beds before starting \(recorderCount) VRecorders. Selected beds: \(selectedBedCount)."
    }

    static func selectedBeds(_ selectedBedCount: Int, _ requiredBedCount: Int, _ availableBedCount: Int) -> String {
        "\(selectedBedCount) selected / \(requiredBedCount) required · \(availableBedCount) available"
    }

    static func startedSession(_ id: String) -> String {
        "Started TestKit session \(id)."
    }

    static func pausedSession(_ id: String) -> String {
        "Paused TestKit session \(id)."
    }

    static func resumedSession(_ id: String) -> String {
        "Resumed TestKit session \(id)."
    }

    static func stoppedSession(_ id: String) -> String {
        "Stopped TestKit session \(id)."
    }

    static func restartedSession(_ id: String) -> String {
        "Restarted TestKit session \(id)."
    }

    static func deletedSession(_ id: String) -> String {
        "Deleted TestKit session \(id)."
    }

    static func deletingVRecorder(_ vrcode: String) -> String {
        "Deleting VRecorder \(vrcode)..."
    }

    static func deletedVRecorder(_ vrcode: String) -> String {
        "Deleted VRecorder \(vrcode)."
    }

    static func failedVRecorderDeletion(_ vrcode: String, _ error: String?) -> String {
        "Failed to delete VRecorder \(vrcode): \(error ?? "unknown error")"
    }

    static func resetSessions(_ count: Int) -> String {
        "Reset \(count) TestKit sessions."
    }
}
