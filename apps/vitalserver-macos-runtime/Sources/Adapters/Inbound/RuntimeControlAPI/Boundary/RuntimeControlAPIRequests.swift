import Foundation
import RuntimeControl

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
    public let lineLimit: Int

    public init(source: RuntimeLogSource, lineLimit: Int) {
        self.source = source
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
