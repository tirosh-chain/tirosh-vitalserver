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
    static let archiveUpload = "Archive upload"
    static let archiveUpdated = "Archive updated"
    static let archiveError = "Archive error"
    static let sessionRecorders = "Session recorders"
    static let productLabResources = "Advanced resources"
    static let vitalFiles = "Vital Files"
    static let uploadToLibrary = "Upload to library"
    static let replayUploadedFile = "Replay uploaded file"
    static let vitalFileSource = ".vital file"
    static let vitalFileFilter = "Filter .vital files"
    static let chooseVitalFilesForUpload = "Choose .vital files"
    static let chooseUploadedVitalFile = "Choose an uploaded .vital file before starting replay."
    static let replayResources = "Replay resources"
    static let quickCreateResources = "Quick create"
    static let useExistingResources = "Use existing"
    static let repeatMode = "Repeat"
    static let repeatOnce = "Once"
    static let repeatCount = "N times"
    static let repeatContinuous = "Continuous"
    static let loadingLabScenarios = "Loading Product Lab scenarios..."
    static let chooseLabScenario = "Choose a Product Lab scenario."
    static let creatingLabSession = "Creating Product Lab session..."
    static let startingLabSession = "Starting Product Lab session..."
    static let stoppingLabSession = "Pausing Product Lab session..."
    static let pause = "Pause"
    static let finishingLabSession = "Finishing Product Lab session and uploading its .vital files..."
    static let finishAndUpload = "Finish & upload"
    static let retryUpload = "Retry upload"
    static let startingLabRecorder = "Starting Product Lab recorder..."
    static let stoppingLabRecorder = "Stopping Product Lab recorder..."
    static let replayingLabVitalFile = "Starting .vital replay session..."
    static let uploadingLabVitalFiles = "Uploading .vital files to the library..."
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
        "Paused Product Lab session \(id)."
    }

    static func finishedLabSession(_ id: String) -> String {
        "Finished Product Lab session \(id) and requested .vital file upload."
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

    static func selectedVitalFiles(_ count: Int) -> String {
        count == 0 ? "No files selected" : "\(count) file(s) selected"
    }

    static func uploadedLabVitalFiles(_ count: Int) -> String {
        "Uploaded \(count) .vital file(s) to the Vital Files library."
    }

    static func repeatTimes(_ count: Int) -> String {
        "\(count) times"
    }
}

enum RuntimeLabActionMessageTone: Equatable, Sendable {
    case neutral
    case failure
}
