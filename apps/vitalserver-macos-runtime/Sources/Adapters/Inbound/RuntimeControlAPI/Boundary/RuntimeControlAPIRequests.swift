import Foundation
import Contracts
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

public struct RuntimeUninstallRequest: Codable, Equatable, Sendable {
    public let mode: RuntimeUninstallMode

    public init(mode: RuntimeUninstallMode) {
        self.mode = mode
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

public struct RuntimeOperationLeaseAcquireRequest: Codable, Equatable, Sendable {
    public let document: RuntimeOperationLeaseDocument

    public init(document: RuntimeOperationLeaseDocument) {
        self.document = document
    }
}

public struct RuntimeOperationLeaseHeartbeatRequest: Codable, Equatable, Sendable {
    public let operationId: String
    public let heartbeatAt: String
    public let expiresAt: String?

    public init(operationId: String, heartbeatAt: String, expiresAt: String?) {
        self.operationId = operationId
        self.heartbeatAt = heartbeatAt
        self.expiresAt = expiresAt
    }
}

public struct RuntimeOperationLeaseReleaseRequest: Codable, Equatable, Sendable {
    public let operationId: String

    public init(operationId: String) {
        self.operationId = operationId
    }
}

public struct RuntimeGuestAddressPutRequest: Codable, Equatable, Sendable {
    public let address: String

    public init(address: String) {
        self.address = address
    }
}

public struct RuntimeVMLifecyclePutRequest: Codable, Equatable, Sendable {
    public let document: RuntimeVMLifecycleDocument

    public init(document: RuntimeVMLifecycleDocument) {
        self.document = document
    }
}
