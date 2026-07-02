enum RuntimeLabPanelText {
    static let summary = "Lab"
    static let description = "Run controlled virtual recorder scenarios and replay local .vital files through the installed VitalServer runtime."
    static let browserChecks = "Browser"
    static let runtimeControlConsole = "Remote Console"
    static let runtimeControlConsoleHelp = "Opens the Remote Console for Runtime Control API status, event streams, and log streams."
    static let productLab = "Product Lab"
    static let choosingVitalFileForPlayback = "Choose .vital file"
    static let chooseVitalFileForPlayback = "Choose a .vital file before starting playback."
    static let chooseSharedVitalFileForPlayback = "Choose a .vital file under the configured vital files directory before starting playback."
    static let loadingLabScenarios = "Loading Product Lab scenarios..."
    static let chooseLabScenario = "Choose a Product Lab scenario."
    static let creatingLabSession = "Creating Product Lab session..."
    static let startingLabSession = "Starting Product Lab session..."
    static let stoppingLabSession = "Stopping Product Lab session..."
    static let replayingLabVitalFile = "Starting .vital replay session..."
    static let noLabSession = "No Product Lab session is selected."
    static let labCapabilityUnavailable = "Product Lab is not available for this runtime connection."

    static func loadedLabScenarios(_ count: Int) -> String {
        "Loaded \(count) Product Lab scenarios."
    }

    static func createdLabSession(_ id: String) -> String {
        "Created Product Lab session \(id)."
    }

    static func startedLabSession(_ id: String) -> String {
        "Started Product Lab session \(id)."
    }

    static func stoppedLabSession(_ id: String) -> String {
        "Stopped Product Lab session \(id)."
    }

    static func replayedLabVitalFile(_ id: String) -> String {
        "Started .vital replay session \(id)."
    }
}

enum RuntimeLabActionMessageTone: Equatable, Sendable {
    case neutral
    case failure
}
