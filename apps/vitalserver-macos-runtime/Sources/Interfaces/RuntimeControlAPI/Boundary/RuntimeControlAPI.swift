import Foundation
import RuntimeControl

public enum RuntimeControlHTTPMethod: String, CaseIterable, Codable, Equatable, Sendable {
    case get = "GET"
    case options = "OPTIONS"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
}

public enum RuntimeControlAPIScope: String, Codable, Equatable, Sendable {
    case runtimeControl
    case hostAffordance
}

public enum RuntimeControlAPIClientAccess: String, Codable, Equatable, Sendable {
    case browserSafe
    case localServerMediated
    case nativeShellOnly
}

public enum RuntimeControlAPIStreamCapability: String, Codable, Equatable, Sendable {
    case supported
    case unsupported
}

public enum RuntimeControlAPIErrorCode: String, Codable, Equatable, Sendable {
    case badRequest
    case routeNotFound
    case methodNotAllowed
    case unauthorized
    case endpointNotImplemented
    case handlerFailed
}

public struct RuntimeControlAPIRoute: Codable, Equatable, Sendable {
    public let method: RuntimeControlHTTPMethod
    public let path: String
    public let scope: RuntimeControlAPIScope

    public init(method: RuntimeControlHTTPMethod, path: String, scope: RuntimeControlAPIScope) {
        self.method = method
        self.path = path
        self.scope = scope
    }
}

public enum RuntimeControlAPIEndpoint: String, CaseIterable, Codable, Equatable, Sendable {
    case capabilities
    case overview
    case overviewStream
    case status
    case statusStream
    case events
    case eventStream
    case vitalDBObservation
    case vitalDBObservationStream
    case vitalDBRecorders
    case vitalDBRecorder
    case vitalDBBeds
    case vitalDBBed
    case vitalDBRelationships
    case health
    case settings
    case applySettings
    case release
    case installInfo
    case startServices
    case stopServices
    case repairRuntimeServices
    case repairProxy
    case repairDatastore
    case repairVMDisk
    case createRedisBackup
    case uninstall
    case backups
    case redisBackups
    case restoreRedisBackup
    case logText
    case logStream
    case updateBundleSummary
    case verifyUpdateBundle
    case applyUpdateBundle
    case rollbackBackup
    case deleteBackup
    case exportLogs

    public var route: RuntimeControlAPIRoute {
        switch self {
        case .capabilities:
            return .init(method: .get, path: "/runtime/capabilities", scope: .runtimeControl)
        case .overview:
            return .init(method: .get, path: "/runtime/overview", scope: .runtimeControl)
        case .overviewStream:
            return .init(method: .get, path: "/runtime/overview/stream", scope: .runtimeControl)
        case .status:
            return .init(method: .get, path: "/runtime/status", scope: .runtimeControl)
        case .statusStream:
            return .init(method: .get, path: "/runtime/status/stream", scope: .runtimeControl)
        case .events:
            return .init(method: .get, path: "/runtime/events", scope: .runtimeControl)
        case .eventStream:
            return .init(method: .get, path: "/runtime/events/stream", scope: .runtimeControl)
        case .vitalDBObservation:
            return .init(method: .get, path: "/vitaldb/observations/latest", scope: .runtimeControl)
        case .vitalDBObservationStream:
            return .init(method: .get, path: "/vitaldb/observations/stream", scope: .runtimeControl)
        case .vitalDBRecorders:
            return .init(method: .get, path: "/vitaldb/recorders", scope: .runtimeControl)
        case .vitalDBRecorder:
            return .init(method: .get, path: "/vitaldb/recorders/{vrcode}", scope: .runtimeControl)
        case .vitalDBBeds:
            return .init(method: .get, path: "/vitaldb/beds", scope: .runtimeControl)
        case .vitalDBBed:
            return .init(method: .get, path: "/vitaldb/beds/{bedID}", scope: .runtimeControl)
        case .vitalDBRelationships:
            return .init(method: .get, path: "/vitaldb/relationships", scope: .runtimeControl)
        case .health:
            return .init(method: .post, path: "/runtime/health", scope: .runtimeControl)
        case .settings:
            return .init(method: .get, path: "/runtime/settings", scope: .runtimeControl)
        case .applySettings:
            return .init(method: .put, path: "/runtime/settings", scope: .runtimeControl)
        case .release:
            return .init(method: .get, path: "/runtime/release", scope: .runtimeControl)
        case .installInfo:
            return .init(method: .get, path: "/runtime/install", scope: .runtimeControl)
        case .startServices:
            return .init(method: .post, path: "/runtime/services/start", scope: .runtimeControl)
        case .stopServices:
            return .init(method: .post, path: "/runtime/services/stop", scope: .runtimeControl)
        case .repairRuntimeServices:
            return .init(method: .post, path: "/runtime/services/repair-runtime", scope: .runtimeControl)
        case .repairProxy:
            return .init(method: .post, path: "/runtime/services/repair-proxy", scope: .runtimeControl)
        case .repairDatastore:
            return .init(method: .post, path: "/runtime/services/repair-datastore", scope: .runtimeControl)
        case .repairVMDisk:
            return .init(method: .post, path: "/runtime/services/repair-vm-disk", scope: .runtimeControl)
        case .createRedisBackup:
            return .init(method: .post, path: "/runtime/redis/backups", scope: .runtimeControl)
        case .uninstall:
            return .init(method: .post, path: "/runtime/uninstall", scope: .runtimeControl)
        case .backups:
            return .init(method: .get, path: "/host/backups", scope: .hostAffordance)
        case .redisBackups:
            return .init(method: .get, path: "/host/backups/redis", scope: .hostAffordance)
        case .restoreRedisBackup:
            return .init(method: .post, path: "/host/backups/redis/restore", scope: .hostAffordance)
        case .logText:
            return .init(method: .post, path: "/host/logs/read", scope: .hostAffordance)
        case .logStream:
            return .init(method: .get, path: "/host/logs/stream", scope: .hostAffordance)
        case .updateBundleSummary:
            return .init(method: .post, path: "/host/update-bundles/summary", scope: .hostAffordance)
        case .verifyUpdateBundle:
            return .init(method: .post, path: "/host/update-bundles/verify", scope: .hostAffordance)
        case .applyUpdateBundle:
            return .init(method: .post, path: "/host/update-bundles/apply", scope: .hostAffordance)
        case .rollbackBackup:
            return .init(method: .post, path: "/host/backups/rollback", scope: .hostAffordance)
        case .deleteBackup:
            return .init(method: .delete, path: "/host/backups", scope: .hostAffordance)
        case .exportLogs:
            return .init(method: .post, path: "/host/logs/export", scope: .hostAffordance)
        }
    }
}

public extension RuntimeControlAPIEndpoint {
    var streamCapability: RuntimeControlAPIStreamCapability {
        switch self {
        case .overviewStream,
             .statusStream,
             .eventStream,
             .vitalDBObservationStream,
             .logStream:
            return .supported
        case .capabilities,
             .overview,
             .status,
             .events,
             .vitalDBObservation,
             .vitalDBRecorders,
             .vitalDBRecorder,
             .vitalDBBeds,
             .vitalDBBed,
             .vitalDBRelationships,
             .health,
             .settings,
             .applySettings,
             .release,
             .installInfo,
             .startServices,
             .stopServices,
             .repairRuntimeServices,
             .repairProxy,
             .repairDatastore,
             .repairVMDisk,
             .createRedisBackup,
             .uninstall,
             .backups,
             .redisBackups,
             .restoreRedisBackup,
             .logText,
             .updateBundleSummary,
             .verifyUpdateBundle,
             .applyUpdateBundle,
             .rollbackBackup,
             .deleteBackup,
             .exportLogs:
            return .unsupported
        }
    }

    var clientAccess: RuntimeControlAPIClientAccess {
        switch self {
        case .capabilities,
             .overview,
             .overviewStream,
             .status,
             .statusStream,
             .events,
             .eventStream,
             .vitalDBObservation,
             .vitalDBObservationStream,
             .vitalDBRecorders,
             .vitalDBRecorder,
             .vitalDBBeds,
             .vitalDBBed,
             .vitalDBRelationships,
             .health,
             .settings,
             .release,
             .installInfo:
            return .browserSafe
        case .exportLogs:
            return .nativeShellOnly
        case .applySettings,
             .startServices,
             .stopServices,
             .repairRuntimeServices,
             .repairProxy,
             .repairDatastore,
             .repairVMDisk,
             .createRedisBackup,
             .uninstall,
             .backups,
             .redisBackups,
             .restoreRedisBackup,
             .logText,
             .logStream,
             .updateBundleSummary,
             .verifyUpdateBundle,
             .applyUpdateBundle,
             .rollbackBackup,
             .deleteBackup:
            return .localServerMediated
        }
    }

    static func matching(method: RuntimeControlHTTPMethod, path: String) -> RuntimeControlAPIEndpoint? {
        allCases.first { endpoint in
            endpoint.route.method == method && endpoint.matches(path: normalizedPath(path))
        }
    }

    static func matching(path: String) -> RuntimeControlAPIEndpoint? {
        allCases.first { endpoint in
            endpoint.matches(path: normalizedPath(path))
        }
    }

    private func matches(path: String) -> Bool {
        switch self {
        case .vitalDBRecorder:
            let components = path.split(separator: "/", omittingEmptySubsequences: true)
            return components.count == 3
                && components[0] == "vitaldb"
                && components[1] == "recorders"
                && !components[2].isEmpty
        case .vitalDBBed:
            let components = path.split(separator: "/", omittingEmptySubsequences: true)
            return components.count == 3
                && components[0] == "vitaldb"
                && components[1] == "beds"
                && !components[2].isEmpty
        default:
            return route.path == path
        }
    }

    private static func normalizedPath(_ path: String) -> String {
        guard let queryIndex = path.firstIndex(of: "?") else {
            return path
        }
        return String(path[..<queryIndex])
    }

    static func normalizedPathForRequest(_ path: String) -> String {
        normalizedPath(path)
    }
}

public enum RuntimeControlFileReferenceKind: String, Codable, Equatable, Sendable {
    case localPath
    case uploadedArtifact
    case remoteURL
}

public struct RuntimeControlFileReference: Codable, Equatable, Sendable {
    public let kind: RuntimeControlFileReferenceKind
    public let value: String

    public init(kind: RuntimeControlFileReferenceKind, value: String) {
        self.kind = kind
        self.value = value
    }
}

public struct RuntimeControlErrorResponse: Codable, Equatable, Sendable {
    public let code: RuntimeControlAPIErrorCode
    public let message: String

    public init(code: RuntimeControlAPIErrorCode, message: String) {
        self.code = code
        self.message = message
    }
}

public enum RuntimeControlErrorResponseEncoder {
    public static func encode(code: RuntimeControlAPIErrorCode, message: String) -> Data {
        Data("{\"code\":\"\(jsonStringContent(code.rawValue))\",\"message\":\"\(jsonStringContent(message))\"}".utf8)
    }

    private static func jsonStringContent(_ value: String) -> String {
        var result = ""
        for scalar in value.unicodeScalars {
            switch scalar {
            case "\"":
                result += "\\\""
            case "\\":
                result += "\\\\"
            case "\u{08}":
                result += "\\b"
            case "\u{0C}":
                result += "\\f"
            case "\n":
                result += "\\n"
            case "\r":
                result += "\\r"
            case "\t":
                result += "\\t"
            case let control where control.value < 0x20:
                result += String(format: "\\u%04X", control.value)
            default:
                result.unicodeScalars.append(scalar)
            }
        }
        return result
    }
}

public struct RuntimeControlCommandResponse: Codable, Equatable, Sendable {
    public let result: RuntimeCommandResult

    public init(result: RuntimeCommandResult) {
        self.result = result
    }
}

public struct RuntimeApplySettingsRequest: Codable, Equatable, Sendable {
    public let settings: RuntimeSettings

    public init(settings: RuntimeSettings) {
        self.settings = settings
    }
}

public struct RuntimeRepairProxyRequest: Codable, Equatable, Sendable {
    public let proxyPort: Int

    public init(proxyPort: Int) {
        self.proxyPort = proxyPort
    }
}

public struct RuntimeUninstallRequest: Codable, Equatable, Sendable {
    public let clean: Bool

    public init(clean: Bool) {
        self.clean = clean
    }
}

public struct RuntimeLogTextRequest: Codable, Equatable, Sendable {
    public let source: RuntimeLogSource
    public let helperMessage: String?
    public let lineLimit: Int

    public init(source: RuntimeLogSource, helperMessage: String? = nil, lineLimit: Int) {
        self.source = source
        self.helperMessage = helperMessage
        self.lineLimit = lineLimit
    }
}

public struct RuntimeLogTextResponse: Codable, Equatable, Sendable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

public struct RuntimeUpdateBundleRequest: Codable, Equatable, Sendable {
    public let bundle: RuntimeControlFileReference

    public init(bundle: RuntimeControlFileReference) {
        self.bundle = bundle
    }
}

public struct RuntimeUpdateBundleSummaryResponse: Codable, Equatable, Sendable {
    public let summary: String

    public init(summary: String) {
        self.summary = summary
    }
}

public struct RuntimeBackupRequest: Codable, Equatable, Sendable {
    public let backup: RuntimeControlFileReference

    public init(backup: RuntimeControlFileReference) {
        self.backup = backup
    }
}

public struct RuntimeExportLogsRequest: Codable, Equatable, Sendable {
    public let destination: RuntimeControlFileReference

    public init(destination: RuntimeControlFileReference) {
        self.destination = destination
    }
}
