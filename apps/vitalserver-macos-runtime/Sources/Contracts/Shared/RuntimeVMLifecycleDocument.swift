import Foundation

public enum RuntimeVMLifecycleState: Codable, Equatable, Sendable {
    case starting
    case bootstrapping
    case running
    case stopping
    case stopped
    case failed
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "starting":
            self = .starting
        case "bootstrapping":
            self = .bootstrapping
        case "running":
            self = .running
        case "stopping":
            self = .stopping
        case "stopped":
            self = .stopped
        case "failed":
            self = .failed
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .starting:
            return "starting"
        case .bootstrapping:
            return "bootstrapping"
        case .running:
            return "running"
        case .stopping:
            return "stopping"
        case .stopped:
            return "stopped"
        case .failed:
            return "failed"
        case .unknown(let value):
            return value
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum RuntimeVMLifecycleTerminalReason: Codable, Equatable, Sendable {
    case launchFailed
    case diskAttachmentInvalid
    case guestFilesystemReadOnly
    case guestDiskIO
    case guestKernelPanic
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "launch-failed":
            self = .launchFailed
        case "disk-attachment-invalid":
            self = .diskAttachmentInvalid
        case "guest-filesystem-read-only":
            self = .guestFilesystemReadOnly
        case "guest-disk-io":
            self = .guestDiskIO
        case "guest-kernel-panic":
            self = .guestKernelPanic
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .launchFailed:
            return "launch-failed"
        case .diskAttachmentInvalid:
            return "disk-attachment-invalid"
        case .guestFilesystemReadOnly:
            return "guest-filesystem-read-only"
        case .guestDiskIO:
            return "guest-disk-io"
        case .guestKernelPanic:
            return "guest-kernel-panic"
        case .unknown(let value):
            return value
        }
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        self.init(rawValue: try container.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public struct RuntimeVMLifecycleDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let state: RuntimeVMLifecycleState
    public let operation: RuntimeOperation?
    public let operationID: String?
    public let bootID: String?
    public let startedAt: String
    public let updatedAt: String
    public let deadlineAt: String?
    public let terminalReason: RuntimeVMLifecycleTerminalReason?
    public let message: String?

    public init(
        schemaVersion: Int = 1,
        state: RuntimeVMLifecycleState,
        operation: RuntimeOperation? = nil,
        operationID: String? = nil,
        bootID: String? = nil,
        startedAt: String,
        updatedAt: String,
        deadlineAt: String? = nil,
        terminalReason: RuntimeVMLifecycleTerminalReason? = nil,
        message: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.state = state
        self.operation = operation
        self.operationID = operationID
        self.bootID = bootID
        self.startedAt = startedAt
        self.updatedAt = updatedAt
        self.deadlineAt = deadlineAt
        self.terminalReason = terminalReason
        self.message = message
    }
}

public extension RuntimeVMLifecycleDocument {
    func isWaitingForGuest(at now: Date, formatter: ISO8601DateFormatter = ISO8601DateFormatter()) -> Bool {
        guard state == .starting || state == .bootstrapping else {
            return false
        }
        guard let deadlineAt,
              let deadline = formatter.date(from: deadlineAt)
        else {
            return false
        }
        return now <= deadline
    }

    var reportedVMErrors: [RuntimeVMError] {
        guard state == .failed, let terminalReason else {
            return []
        }
        switch terminalReason {
        case .launchFailed:
            return [.launchFailed(terminalReason.rawValue)]
        case .diskAttachmentInvalid:
            return [.diskAttachmentInvalid]
        case .guestFilesystemReadOnly:
            return [.guestFilesystemReadOnly]
        case .guestDiskIO:
            return [.guestDiskIO]
        case .guestKernelPanic:
            return [.guestFilesystemError]
        case .unknown(let value):
            return [.unknown("vm-lifecycle-\(value)")]
        }
    }
}
