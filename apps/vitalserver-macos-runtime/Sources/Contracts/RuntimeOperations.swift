import Foundation

public enum RuntimeOperation: Codable, Equatable, Sendable {
    case install
    case status
    case health
    case watchdog
    case configure
    case verifyBundle
    case stageBundle
    case applyBundle
    case prepareUpdateShutdown
    case activateGuestUpdate
    case rollback
    case redisBackup
    case repairDatastore
    case repairVMDisk
    case repairProxy
    case repairServices
    case startServices
    case stopServices
    case uninstall
    case unknown(String)

    public init(rawValue: String) {
        switch rawValue {
        case "install":
            self = .install
        case "status":
            self = .status
        case "health":
            self = .health
        case "watchdog":
            self = .watchdog
        case "configure":
            self = .configure
        case "verify-bundle":
            self = .verifyBundle
        case "stage-bundle":
            self = .stageBundle
        case "apply-bundle":
            self = .applyBundle
        case "prepare-update-shutdown":
            self = .prepareUpdateShutdown
        case "activate-guest-update", "activate-update":
            self = .activateGuestUpdate
        case "rollback":
            self = .rollback
        case "redis-backup":
            self = .redisBackup
        case "repair-datastore":
            self = .repairDatastore
        case "repair-vm-disk":
            self = .repairVMDisk
        case "repair-proxy":
            self = .repairProxy
        case "repair-services":
            self = .repairServices
        case "start-services":
            self = .startServices
        case "stop-services":
            self = .stopServices
        case "uninstall":
            self = .uninstall
        default:
            self = .unknown(rawValue)
        }
    }

    public var rawValue: String {
        switch self {
        case .install:
            return "install"
        case .status:
            return "status"
        case .health:
            return "health"
        case .watchdog:
            return "watchdog"
        case .configure:
            return "configure"
        case .verifyBundle:
            return "verify-bundle"
        case .stageBundle:
            return "stage-bundle"
        case .applyBundle:
            return "apply-bundle"
        case .prepareUpdateShutdown:
            return "prepare-update-shutdown"
        case .activateGuestUpdate:
            return "activate-guest-update"
        case .rollback:
            return "rollback"
        case .redisBackup:
            return "redis-backup"
        case .repairDatastore:
            return "repair-datastore"
        case .repairVMDisk:
            return "repair-vm-disk"
        case .repairProxy:
            return "repair-proxy"
        case .repairServices:
            return "repair-services"
        case .startServices:
            return "start-services"
        case .stopServices:
            return "stop-services"
        case .uninstall:
            return "uninstall"
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
