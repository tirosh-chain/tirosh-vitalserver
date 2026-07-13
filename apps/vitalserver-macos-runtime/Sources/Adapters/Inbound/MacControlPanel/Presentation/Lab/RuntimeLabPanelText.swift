enum RuntimeLabPanelText {
    static let summary = "Lab"
    static let description = "Run controlled virtual recorder scenarios and replay local .vital files through the installed VitalServer runtime."
    static let browserChecks = "Browser"
    static let runtimeControlConsole = "Remote Console"
    static let runtimeControlConsoleHelp = "Opens the Remote Console for Runtime Control API status, event streams, and log streams."
    static let productLab = "Product Lab"
    static let productLabSession = "New scenario session"
    static let productLabSessions = "Sessions"
    static let selectedLabSession = "Selected session"
    static let sessionRecorders = "Session recorders"
    static let productLabResources = "Advanced resources"
    static let vitalFileReplay = ".vital replay"
    static let vitalFileSource = ".vital file"
    static let vitalFileFilter = "Filter .vital files"
    static let choosingVitalFileForPlayback = "Choose .vital file"
    static let chooseVitalFileForPlayback = "Choose a .vital file before starting playback."
    static let chooseSharedVitalFileForPlayback = "Choose a .vital file under the configured vital files directory before starting playback."
    static let loadingLabScenarios = "Loading Product Lab scenarios..."
    static let chooseLabScenario = "Choose a Product Lab scenario."
    static let creatingLabSession = "Creating Product Lab session..."
    static let startingLabSession = "Starting Product Lab session..."
    static let stoppingLabSession = "Stopping Product Lab session..."
    static let startingLabRecorder = "Starting Product Lab recorder..."
    static let stoppingLabRecorder = "Stopping Product Lab recorder..."
    static let replayingLabVitalFile = "Starting .vital replay session..."
    static let uploadingLabVitalFile = "Uploading .vital file..."
    static let uploadFailed = ".vital file upload failed."
    static let labTargetURLRequired = "Target URL is required."
    static let noLabSession = "No Product Lab session is selected."
    static let runningLabSessionRequired = "Select a running Product Lab session to control its recorders."
    static let chooseSessionLabRecorder = "Choose a recorder owned by the selected Product Lab session."
    static let labRecorderCommandFailed = "Product Lab recorder command failed."
    static let labCapabilityUnavailable = "Product Lab is not available for this runtime connection."
    static let labTargetURL = "Target URL"
    static let labSessionBedIDs = "Advanced bed IDs"
    static let useSelectedLabBed = "Use selected bed"
    static let labBedManagement = "Beds"
    static let labRecorderManagement = "Recorders"
    static let chooseLabBed = "Choose a Lab bed."
    static let chooseLabRecorder = "Choose a Lab recorder."
    static let creatingLabBeds = "Creating Lab beds..."
    static let deletingLabBed = "Deleting Lab bed..."
    static let resettingLabBeds = "Resetting Lab beds..."
    static let creatingLabRecorder = "Creating Lab recorder..."
    static let deletingLabRecorder = "Deleting Lab recorder..."
    static let resettingLabRecorders = "Resetting Lab recorders..."
    static let deletedLabBed = "Deleted Lab bed."
    static let resetLabBeds = "Reset Lab beds."
    static let createdLabRecorder = "Created Lab recorder."
    static let deletedLabRecorder = "Deleted Lab recorder."
    static let resetLabRecorders = "Reset Lab recorders."
    static let messagesSent = "Messages"
    static let lastSend = "Last send"

    static func loadedLabScenarios(_ count: Int) -> String {
        "Loaded \(count) Product Lab scenarios."
    }

    static func createdLabBeds(_ count: Int) -> String {
        "Loaded \(count) Lab beds."
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

    static func startedLabRecorder(_ vrcode: String) -> String {
        "Started Product Lab recorder \(vrcode)."
    }

    static func stoppedLabRecorder(_ vrcode: String) -> String {
        "Stopped Product Lab recorder \(vrcode)."
    }

    static func replayedLabVitalFile(_ id: String) -> String {
        "Started .vital replay session \(id)."
    }

    static func uploadedLabVitalFile(_ filename: String) -> String {
        "Uploaded .vital file \(filename)."
    }
}

enum RuntimeLabActionMessageTone: Equatable, Sendable {
    case neutral
    case failure
}
