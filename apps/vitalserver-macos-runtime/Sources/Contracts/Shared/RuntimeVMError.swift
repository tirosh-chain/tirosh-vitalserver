public enum RuntimeVMErrorCategory: String, Codable, Equatable, Sendable {
    case installation
    case lifecycle
    case networking
    case guestAgent
    case guestBootstrap
    case guestStorage
    case configuration
    case hostResources
    case unknown
}

public enum RuntimeVMRecoveryAction: String, Codable, Equatable, Sendable {
    case installRuntime
    case restartVMService
    case waitForGuest
    case restartGuestAgent
    case repairGuestBootstrap
    case backupAndRecreateVM
    case fixConfiguration
    case freeHostResources
    case inspectLogs
}

public enum RuntimeVMError: Codable, Equatable, Sendable {
    case missingExecutable
    case missingRootfsBase
    case missingDisk
    case serviceNotLoaded(String)
    case missingIPAddress
    case launchFailed(String)
    case invalidConfiguration(String)
    case hostResourceUnavailable(String)
    case diskAttachmentInvalid
    case guestFilesystemError
    case guestFilesystemReadOnly
    case guestDiskIO
    case guestHTTP(String)
    case guestHTTPProbeFailed(String)
    case guestBootstrapMissingRuntimePackages
    case guestBootstrapDockerRuntimeFailed
    case guestBootstrapFailed
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "vm-missing-executable":
            self = .missingExecutable
        case "vm-missing-rootfs-base":
            self = .missingRootfsBase
        case "vm-missing-disk":
            self = .missingDisk
        case "vm-missing-ip-address":
            self = .missingIPAddress
        case "vm-disk-attachment-invalid":
            self = .diskAttachmentInvalid
        case "vm-guest-filesystem-error":
            self = .guestFilesystemError
        case "vm-guest-filesystem-read-only":
            self = .guestFilesystemReadOnly
        case "vm-guest-disk-io-error":
            self = .guestDiskIO
        case "vm-guest-bootstrap-missing-runtime-packages":
            self = .guestBootstrapMissingRuntimePackages
        case "vm-guest-bootstrap-docker-runtime-failed":
            self = .guestBootstrapDockerRuntimeFailed
        case "vm-guest-bootstrap-failed":
            self = .guestBootstrapFailed
        default:
            if rawValue.hasPrefix("vm-service-state-") {
                self = .serviceNotLoaded(String(rawValue.dropFirst("vm-service-state-".count)))
            } else if rawValue.hasPrefix("vm-launch-failed-") {
                self = .launchFailed(String(rawValue.dropFirst("vm-launch-failed-".count)))
            } else if rawValue.hasPrefix("vm-invalid-configuration-") {
                self = .invalidConfiguration(String(rawValue.dropFirst("vm-invalid-configuration-".count)))
            } else if rawValue.hasPrefix("vm-host-resource-unavailable-") {
                self = .hostResourceUnavailable(String(rawValue.dropFirst("vm-host-resource-unavailable-".count)))
            } else if rawValue.hasPrefix("vm-guest-http-probe-failed-") {
                self = .guestHTTPProbeFailed(String(rawValue.dropFirst("vm-guest-http-probe-failed-".count)))
            } else if rawValue.hasPrefix("vm-guest-http-") {
                self = .guestHTTP(String(rawValue.dropFirst("vm-guest-http-".count)))
            } else {
                self = .unknown(rawValue)
            }
        }
    }

    public var rawValue: String {
        switch self {
        case .missingExecutable:
            "vm-missing-executable"
        case .missingRootfsBase:
            "vm-missing-rootfs-base"
        case .missingDisk:
            "vm-missing-disk"
        case .serviceNotLoaded(let state):
            "vm-service-state-\(state)"
        case .missingIPAddress:
            "vm-missing-ip-address"
        case .launchFailed(let reason):
            "vm-launch-failed-\(reason)"
        case .invalidConfiguration(let subject):
            "vm-invalid-configuration-\(subject)"
        case .hostResourceUnavailable(let subject):
            "vm-host-resource-unavailable-\(subject)"
        case .diskAttachmentInvalid:
            "vm-disk-attachment-invalid"
        case .guestFilesystemError:
            "vm-guest-filesystem-error"
        case .guestFilesystemReadOnly:
            "vm-guest-filesystem-read-only"
        case .guestDiskIO:
            "vm-guest-disk-io-error"
        case .guestHTTP(let status):
            "vm-guest-http-\(status)"
        case .guestHTTPProbeFailed(let status):
            "vm-guest-http-probe-failed-\(status)"
        case .guestBootstrapMissingRuntimePackages:
            "vm-guest-bootstrap-missing-runtime-packages"
        case .guestBootstrapDockerRuntimeFailed:
            "vm-guest-bootstrap-docker-runtime-failed"
        case .guestBootstrapFailed:
            "vm-guest-bootstrap-failed"
        case .unknown(let value):
            value
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

public extension RuntimeVMError {
    var category: RuntimeVMErrorCategory {
        switch self {
        case .missingExecutable, .missingRootfsBase, .missingDisk:
            return .installation
        case .serviceNotLoaded, .launchFailed:
            return .lifecycle
        case .missingIPAddress, .guestHTTP, .guestHTTPProbeFailed:
            return .networking
        case .guestBootstrapMissingRuntimePackages, .guestBootstrapDockerRuntimeFailed, .guestBootstrapFailed:
            return .guestBootstrap
        case .diskAttachmentInvalid, .guestFilesystemError, .guestFilesystemReadOnly, .guestDiskIO:
            return .guestStorage
        case .invalidConfiguration:
            return .configuration
        case .hostResourceUnavailable:
            return .hostResources
        case .unknown:
            return .unknown
        }
    }

    var recoveryAction: RuntimeVMRecoveryAction {
        switch self {
        case .missingExecutable, .missingRootfsBase, .missingDisk:
            return .installRuntime
        case .serviceNotLoaded:
            return .restartVMService
        case .missingIPAddress, .guestHTTP, .guestHTTPProbeFailed:
            return .waitForGuest
        case .guestBootstrapMissingRuntimePackages, .guestBootstrapDockerRuntimeFailed, .guestBootstrapFailed:
            return .repairGuestBootstrap
        case .diskAttachmentInvalid, .guestFilesystemError, .guestFilesystemReadOnly, .guestDiskIO:
            return .backupAndRecreateVM
        case .launchFailed:
            return .inspectLogs
        case .invalidConfiguration:
            return .fixConfiguration
        case .hostResourceUnavailable:
            return .freeHostResources
        case .unknown:
            return .inspectLogs
        }
    }

    var requiresDataPreservationBeforeRecovery: Bool {
        recoveryAction == .backupAndRecreateVM
    }
}
