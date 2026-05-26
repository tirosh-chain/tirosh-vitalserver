public enum RuntimeVMError: Codable, Equatable, Sendable {
    case missingExecutable
    case missingRootfsBase
    case missingDisk
    case serviceNotLoaded(String)
    case missingIPAddress
    case runtimeStateStale
    case diskAttachmentInvalid
    case guestFilesystemError
    case guestFilesystemReadOnly
    case guestDiskIO
    case guestHTTP(String)
    case guestBootstrapMissingRuntimePackages
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
        case "vm-runtime-state-stale":
            self = .runtimeStateStale
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
        case "vm-guest-bootstrap-failed":
            self = .guestBootstrapFailed
        default:
            if rawValue.hasPrefix("vm-service-state-") {
                self = .serviceNotLoaded(String(rawValue.dropFirst("vm-service-state-".count)))
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
        case .runtimeStateStale:
            "vm-runtime-state-stale"
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
        case .guestBootstrapMissingRuntimePackages:
            "vm-guest-bootstrap-missing-runtime-packages"
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
