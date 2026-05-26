import Contracts
import Core
import Foundation

public struct RuntimeBackup: Codable, Identifiable, Hashable, Sendable {
    public let path: String
    public let sizeBytes: UInt64?

    public init(path: String, sizeBytes: UInt64?) {
        self.path = path
        self.sizeBytes = sizeBytes
    }

    public var id: String { path }
    public var name: String { URL(fileURLWithPath: path).lastPathComponent }
}

public enum RuntimeLogSource: String, Codable, Hashable, Sendable {
    case helperMessage
    case install
    case command
    case launcher
    case proxyOutput
    case proxyError
    case updateActivation
    case containers
}

public struct RuntimeLogSourceOption: Codable, Identifiable, Sendable {
    public let id: RuntimeLogSource
    public let title: String

    public init(id: RuntimeLogSource, title: String) {
        self.id = id
        self.title = title
    }
}

public struct VitalFilesFolder: Codable, Identifiable, Sendable {
    public var id: String { path }
    public let name: String
    public let path: String

    public init(name: String, path: String) {
        self.name = name
        self.path = path
    }
}

public struct RuntimeCommandResult: Codable, Equatable, Sendable {
    public let exitCode: Int32
    public let stdout: String
    public let stderr: String

    public init(exitCode: Int32, stdout: String, stderr: String) {
        self.exitCode = exitCode
        self.stdout = stdout
        self.stderr = stderr
    }
}

public struct RuntimeLogExportResult: Codable, Equatable, Sendable {
    public let destination: URL

    public init(destination: URL) {
        self.destination = destination
    }
}

public struct RuntimeReleaseInfo: Codable, Equatable, Sendable {
    public let helperVersion: String
    public let minimumUpdaterVersion: String
    public let vitalServerVersion: String
    public let services: [RuntimeBundledServiceInfo]

    public init(
        helperVersion: String,
        minimumUpdaterVersion: String,
        vitalServerVersion: String,
        services: [RuntimeBundledServiceInfo]
    ) {
        self.helperVersion = helperVersion
        self.minimumUpdaterVersion = minimumUpdaterVersion
        self.vitalServerVersion = vitalServerVersion
        self.services = services
    }
}

public struct RuntimeBundledServiceInfo: Codable, Equatable, Identifiable, Sendable {
    public var id: String { name }
    public let name: String
    public let image: String
    public let version: String

    public init(name: String, image: String, version: String) {
        self.name = name
        self.image = image
        self.version = version
    }
}

public struct RuntimeInstallInfo: Codable, Equatable, Sendable {
    public let appBundlePath: String
    public let packageIdentifier: String
    public let runtimeHomePath: String
    public let backupsPath: String
    public let redisBackupsPath: String

    public init(
        appBundlePath: String = "",
        packageIdentifier: String = "",
        runtimeHomePath: String = "",
        backupsPath: String = "",
        redisBackupsPath: String? = nil
    ) {
        self.appBundlePath = appBundlePath
        self.packageIdentifier = packageIdentifier
        self.runtimeHomePath = runtimeHomePath
        self.backupsPath = backupsPath
        self.redisBackupsPath = redisBackupsPath ?? ""
    }
}

public struct RuntimeEventHistory: Codable, Equatable, Sendable {
    public let events: [RuntimeEventDocument]
    public let nextCursor: String?

    public init(events: [RuntimeEventDocument], nextCursor: String? = nil) {
        self.events = events
        self.nextCursor = nextCursor
    }
}
