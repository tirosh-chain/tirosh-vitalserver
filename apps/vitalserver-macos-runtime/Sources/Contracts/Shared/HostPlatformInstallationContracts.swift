public enum HostPlatformReleaseArchiveContract {
  public static let mediaType =
    "application/vnd.tirosh.vitalserver-helper.host-platform-release+tar+gzip"
  public static let manifestSchemaVersion =
    "vitalserver.helper-host-platform-release-manifest/v1"
}

public enum HostPlatformInstallationContract {
  public static let manifestSchemaVersion =
    "vitalserver.host-platform-installation/v1"
  public static let operationSchemaVersion =
    "vitalserver.host-platform-installation-operation/v1"
  public static let serviceRequestSchemaVersion =
    "vitalserver.host-platform-service-reconciliation/v1"
  public static let serviceReceiptSchemaVersion =
    "vitalserver.host-platform-service-reconciliation-receipt/v1"
}

public struct HostPlatformRelease: Codable, Equatable, Sendable {
  public let id: String
  public let version: String
  public let sha256: String
  public let slotRelativePath: String

  public init(id: String, version: String, sha256: String, slotRelativePath: String) {
    self.id = id
    self.version = version
    self.sha256 = sha256
    self.slotRelativePath = slotRelativePath
  }
}

public struct HostPlatformInstallationManifest: Codable, Equatable, Sendable {
  public let schemaVersion: String
  public let installationId: String
  public let installationRevision: Int
  public let activeRelease: HostPlatformRelease
  public let rollbackRelease: HostPlatformRelease?
  public let activationOperationId: String
  public let activatedAt: String

  public init(
    schemaVersion: String,
    installationId: String,
    installationRevision: Int,
    activeRelease: HostPlatformRelease,
    rollbackRelease: HostPlatformRelease?,
    activationOperationId: String,
    activatedAt: String
  ) {
    self.schemaVersion = schemaVersion
    self.installationId = installationId
    self.installationRevision = installationRevision
    self.activeRelease = activeRelease
    self.rollbackRelease = rollbackRelease
    self.activationOperationId = activationOperationId
    self.activatedAt = activatedAt
  }
}

public enum HostPlatformInstallationOperationKind: String, Codable, Equatable, Sendable {
  case apply
  case rollback
}

public enum HostPlatformInstallationOperationState: String, Codable, Equatable, Sendable {
  case requested
  case candidateStaged = "candidate-staged"
  case servicesReconciled = "services-reconciled"
  case succeeded
  case failed
}

public struct HostPlatformStagedCandidate: Codable, Equatable, Sendable {
  public let release: HostPlatformRelease
  public let stagingReceiptId: String
  public let stagedAt: String

  public init(
    release: HostPlatformRelease,
    stagingReceiptId: String,
    stagedAt: String
  ) {
    self.release = release
    self.stagingReceiptId = stagingReceiptId
    self.stagedAt = stagedAt
  }
}

public enum HostPlatformServiceReconciliationOutcome: String, Codable, Equatable, Sendable {
  case succeeded
  case failed
}

public struct HostPlatformServiceReconciliationReceipt: Codable, Equatable, Sendable {
  public let schemaVersion: String
  public let reconciliationId: String
  public let operationId: String
  public let installationId: String
  public let expectedInstallationRevision: Int
  public let targetReleaseId: String
  public let targetReleaseSHA256: String
  public let outcome: HostPlatformServiceReconciliationOutcome
  public let observedAt: String
  public let failureReason: String?

  public init(
    schemaVersion: String,
    reconciliationId: String,
    operationId: String,
    installationId: String,
    expectedInstallationRevision: Int,
    targetReleaseId: String,
    targetReleaseSHA256: String,
    outcome: HostPlatformServiceReconciliationOutcome,
    observedAt: String,
    failureReason: String?
  ) {
    self.schemaVersion = schemaVersion
    self.reconciliationId = reconciliationId
    self.operationId = operationId
    self.installationId = installationId
    self.expectedInstallationRevision = expectedInstallationRevision
    self.targetReleaseId = targetReleaseId
    self.targetReleaseSHA256 = targetReleaseSHA256
    self.outcome = outcome
    self.observedAt = observedAt
    self.failureReason = failureReason
  }
}

public struct HostPlatformInstallationOperation: Codable, Equatable, Sendable {
  public let schemaVersion: String
  public let id: String
  public let operationRevision: Int
  public let kind: HostPlatformInstallationOperationKind
  public let state: HostPlatformInstallationOperationState
  public let installationId: String
  public let expectedInstallationRevision: Int
  public let targetRelease: HostPlatformRelease
  public let previousRelease: HostPlatformRelease
  public let candidate: HostPlatformStagedCandidate?
  public let serviceReceipt: HostPlatformServiceReconciliationReceipt?
  public let failureReason: String?
  public let requestedAt: String
  public let updatedAt: String

  public init(
    schemaVersion: String,
    id: String,
    operationRevision: Int,
    kind: HostPlatformInstallationOperationKind,
    state: HostPlatformInstallationOperationState,
    installationId: String,
    expectedInstallationRevision: Int,
    targetRelease: HostPlatformRelease,
    previousRelease: HostPlatformRelease,
    candidate: HostPlatformStagedCandidate?,
    serviceReceipt: HostPlatformServiceReconciliationReceipt?,
    failureReason: String?,
    requestedAt: String,
    updatedAt: String
  ) {
    self.schemaVersion = schemaVersion
    self.id = id
    self.operationRevision = operationRevision
    self.kind = kind
    self.state = state
    self.installationId = installationId
    self.expectedInstallationRevision = expectedInstallationRevision
    self.targetRelease = targetRelease
    self.previousRelease = previousRelease
    self.candidate = candidate
    self.serviceReceipt = serviceReceipt
    self.failureReason = failureReason
    self.requestedAt = requestedAt
    self.updatedAt = updatedAt
  }
}

public struct HostPlatformInstallationCommand: Codable, Equatable, Sendable {
  public let operationId: String
  public let kind: HostPlatformInstallationOperationKind
  public let installationId: String
  public let expectedInstallationRevision: Int
  public let targetRelease: HostPlatformRelease
  public let sourceArtifactPath: String
  public let sourceArtifactSizeBytes: UInt64
  public let sourceArtifactMediaType: String
  public let stagingAttemptId: String
  public let requestedAt: String

  public init(
    operationId: String,
    kind: HostPlatformInstallationOperationKind,
    installationId: String,
    expectedInstallationRevision: Int,
    targetRelease: HostPlatformRelease,
    sourceArtifactPath: String,
    sourceArtifactSizeBytes: UInt64,
    sourceArtifactMediaType: String,
    stagingAttemptId: String,
    requestedAt: String
  ) {
    self.operationId = operationId
    self.kind = kind
    self.installationId = installationId
    self.expectedInstallationRevision = expectedInstallationRevision
    self.targetRelease = targetRelease
    self.sourceArtifactPath = sourceArtifactPath
    self.sourceArtifactSizeBytes = sourceArtifactSizeBytes
    self.sourceArtifactMediaType = sourceArtifactMediaType
    self.stagingAttemptId = stagingAttemptId
    self.requestedAt = requestedAt
  }
}

public struct HostPlatformServiceReconciliationRequest: Codable, Equatable, Sendable {
  public let schemaVersion: String
  public let reconciliationId: String
  public let operationId: String
  public let installationId: String
  public let expectedInstallationRevision: Int
  public let targetRelease: HostPlatformRelease
  public let previousRelease: HostPlatformRelease

  public init(
    schemaVersion: String,
    reconciliationId: String,
    operationId: String,
    installationId: String,
    expectedInstallationRevision: Int,
    targetRelease: HostPlatformRelease,
    previousRelease: HostPlatformRelease
  ) {
    self.schemaVersion = schemaVersion
    self.reconciliationId = reconciliationId
    self.operationId = operationId
    self.installationId = installationId
    self.expectedInstallationRevision = expectedInstallationRevision
    self.targetRelease = targetRelease
    self.previousRelease = previousRelease
  }
}

public struct HostPlatformReleaseArchiveManifest:
  Codable,
  Equatable,
  Sendable
{
  public let schemaVersion: String
  public let installationId: String
  public let release: HostPlatformReleaseIdentity
  public let releaseCatalogPath: String
  public let releaseRootPath: String
  public let currentReleaseLinkPath: String
  public let files: [HostPlatformImmutablePayloadEntry]
  public let operatorInterface: HostPlatformOperatorInterface
  public let replaceableServices: [HostPlatformRequiredService]
  public let stableComponents: [HostPlatformStableComponent]
  public let mutableStores: [HostPlatformMutableStore]
}

public struct HostPlatformReleaseIdentity: Codable, Equatable, Sendable {
  public let id: String
  public let version: String
}

public struct HostPlatformImmutablePayloadEntry:
  Codable,
  Equatable,
  Sendable
{
  public let relativePath: String
  public let sha256: String
  public let executable: Bool
}

public struct HostPlatformOperatorInterface: Codable, Equatable, Sendable {
  public let bootstrapConfigurationPath: String
  public let bootstrapConfigurationSha256: String
  public let applicationBundlePath: String
  public let applicationBundleRelativePath: String
  public let applicationBundleTreeSha256: String
  public let applicationBundleEntrypointRelativePath: String
}

public struct HostPlatformRequiredService: Codable, Equatable, Sendable {
  public let role: String
  public let manager: String
  public let name: String
  public let definitionPath: String
  public let definitionSha256: String
}

public struct HostPlatformStableComponent: Codable, Equatable, Sendable {
  public let role: String
  public let executablePath: String
  public let serviceName: String?
}

public struct HostPlatformMutableStore: Codable, Equatable, Sendable {
  public let id: String
  public let path: String
  public let kind: String
  public let owner: String
  public let retention: String
}
