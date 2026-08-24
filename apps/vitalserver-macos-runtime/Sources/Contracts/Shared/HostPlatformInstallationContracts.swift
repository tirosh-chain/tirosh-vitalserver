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
}

/// A reconciliation error that carries an explicit, structured failure reason
/// for the durable journal instead of requiring callers to stringify it.
public protocol HostPlatformReconciliationFailure: Error {
  var reconciliationReason: String { get }
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

/// Durable lifecycle phase of a Host Platform installation operation.
///
/// Each completed effect is persisted as the next phase in the operation
/// document (via CAS on `operationRevision`) before the workflow begins another
/// effect. On restart, the workflow resumes from the durable phase and
/// reconciles it against Host-owned typed observations.
public enum HostPlatformInstallationPhase: String, Codable, Equatable, Sendable {
  /// Operation was admitted but no irreversible effect has run yet.
  case requested
  /// Candidate archive has been staged and its exact closure verified.
  case prepared
  /// Previous release replaceable services were quiesced (confirmed not loaded).
  case previousQuiesced = "previous-quiesced"
  /// Service definitions, operator bootstrap, and operator app were published.
  case interfacesPublished = "interfaces-published"
  /// `current` symlink was switched to the target release root.
  case targetActivated = "target-activated"
  /// Target release replaceable services were loaded with an explicit loaded proof.
  case targetServicesLoaded = "target-services-loaded"
  /// Compensation is in progress (target effects are being undone).
  case compensating
  /// Compensation completed; the previous release was restored.
  case compensated
  /// Operation settled successfully (receipt + manifest advanced).
  case completed
  /// Operation failed terminally.
  case failed
}

/// One irreversible Host Platform effect, recorded in the durable journal.
public enum HostPlatformReconciliationEffect: String, Codable, Equatable, Sendable {
  case stageCandidate = "stage-candidate"
  case quiescePrevious = "quiesce-previous"
  case publishInterfaces = "publish-interfaces"
  case activateTarget = "activate-target"
  case loadTargetServices = "load-target-services"
  case compensate = "compensate"
  case settle = "settle"
  case fail = "fail"
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

/// A launchd command issued during reconciliation.
public enum HostPlatformLaunchdAction: String, Codable, Equatable, Sendable {
  case bootout
  case bootstrap
  case print
}

/// Typed, exit-code-only launchd outcome. Never derived from stderr text, so the
/// classification is stable across locales.
public enum HostPlatformLaunchdOutcome: String, Codable, Equatable, Sendable {
  /// `bootout`/`bootstrap` accepted (exit 0). `bootstrap` acceptance is not a
  /// running/healthy proof; it only means launchd accepted the load request.
  case accepted
  /// `print` returned exit 0: the service is loaded.
  case loaded
  /// `print` reported the service is not loaded.
  case notLoaded = "not-loaded"
  /// `bootout` reported the service was already not loaded (idempotent desired
  /// outcome; not an error).
  case alreadyNotLoaded = "already-not-loaded"
  case permissionDenied = "permission-denied"
  case failed
}

public struct HostPlatformLaunchdServiceObservation: Codable, Equatable, Sendable {
  public let role: String
  public let serviceName: String
  public let action: HostPlatformLaunchdAction
  public let exitCode: Int32
  public let outcome: HostPlatformLaunchdOutcome

  public init(
    role: String,
    serviceName: String,
    action: HostPlatformLaunchdAction,
    exitCode: Int32,
    outcome: HostPlatformLaunchdOutcome
  ) {
    self.role = role
    self.serviceName = serviceName
    self.action = action
    self.exitCode = exitCode
    self.outcome = outcome
  }
}

/// Host-owned read of the `current` release symlink target.
public enum HostPlatformCurrentReleaseTargetRead: Codable, Equatable, Sendable {
  case resolved(String)
  case notSymlink
  case missing
  case readFailed(String)

  public init(rawValue: String) {
    switch rawValue {
    case "not-symlink":
      self = .notSymlink
    case "missing":
      self = .missing
    default:
      if rawValue.hasPrefix("resolved: ") {
        self = .resolved(String(rawValue.dropFirst("resolved: ".count)))
      } else if rawValue.hasPrefix("read-failed: ") {
        self = .readFailed(String(rawValue.dropFirst("read-failed: ".count)))
      } else {
        self = .readFailed(rawValue)
      }
    }
  }

  public var rawValue: String {
    switch self {
    case .resolved(let path):
      "resolved: \(path)"
    case .notSymlink:
      "not-symlink"
    case .missing:
      "missing"
    case .readFailed(let reason):
      "read-failed: \(reason)"
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

/// One durable journal record, written before/after an irreversible effect.
public struct HostPlatformReconciliationJournalEntry: Codable, Equatable, Sendable {
  public let effect: HostPlatformReconciliationEffect
  public let phase: HostPlatformInstallationPhase
  /// Resolved `current` symlink target after activation, when applicable.
  public let currentReleaseTarget: String?
  /// Launchd observations recorded by this effect.
  public let services: [HostPlatformLaunchdServiceObservation]
  public let observedAt: String

  public init(
    effect: HostPlatformReconciliationEffect,
    phase: HostPlatformInstallationPhase,
    currentReleaseTarget: String?,
    services: [HostPlatformLaunchdServiceObservation],
    observedAt: String
  ) {
    self.effect = effect
    self.phase = phase
    self.currentReleaseTarget = currentReleaseTarget
    self.services = services
    self.observedAt = observedAt
  }
}

public struct HostPlatformInstallationOperation: Codable, Equatable, Sendable {
  public let schemaVersion: String
  public let id: String
  public let operationRevision: Int
  public let kind: HostPlatformInstallationOperationKind
  public let phase: HostPlatformInstallationPhase
  public let installationId: String
  public let expectedInstallationRevision: Int
  public let targetRelease: HostPlatformRelease
  public let previousRelease: HostPlatformRelease
  public let candidate: HostPlatformStagedCandidate?
  public let journal: [HostPlatformReconciliationJournalEntry]
  public let failureReason: String?
  public let requestedAt: String
  public let updatedAt: String

  public init(
    schemaVersion: String,
    id: String,
    operationRevision: Int,
    kind: HostPlatformInstallationOperationKind,
    phase: HostPlatformInstallationPhase,
    installationId: String,
    expectedInstallationRevision: Int,
    targetRelease: HostPlatformRelease,
    previousRelease: HostPlatformRelease,
    candidate: HostPlatformStagedCandidate?,
    journal: [HostPlatformReconciliationJournalEntry],
    failureReason: String?,
    requestedAt: String,
    updatedAt: String
  ) {
    self.schemaVersion = schemaVersion
    self.id = id
    self.operationRevision = operationRevision
    self.kind = kind
    self.phase = phase
    self.installationId = installationId
    self.expectedInstallationRevision = expectedInstallationRevision
    self.targetRelease = targetRelease
    self.previousRelease = previousRelease
    self.candidate = candidate
    self.journal = journal
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

  public init(
    schemaVersion: String,
    installationId: String,
    release: HostPlatformReleaseIdentity,
    releaseCatalogPath: String,
    releaseRootPath: String,
    currentReleaseLinkPath: String,
    files: [HostPlatformImmutablePayloadEntry],
    operatorInterface: HostPlatformOperatorInterface,
    replaceableServices: [HostPlatformRequiredService],
    stableComponents: [HostPlatformStableComponent],
    mutableStores: [HostPlatformMutableStore]
  ) {
    self.schemaVersion = schemaVersion
    self.installationId = installationId
    self.release = release
    self.releaseCatalogPath = releaseCatalogPath
    self.releaseRootPath = releaseRootPath
    self.currentReleaseLinkPath = currentReleaseLinkPath
    self.files = files
    self.operatorInterface = operatorInterface
    self.replaceableServices = replaceableServices
    self.stableComponents = stableComponents
    self.mutableStores = mutableStores
  }
}

public struct HostPlatformReleaseIdentity: Codable, Equatable, Sendable {
  public let id: String
  public let version: String

  public init(id: String, version: String) {
    self.id = id
    self.version = version
  }
}

public struct HostPlatformImmutablePayloadEntry:
  Codable,
  Equatable,
  Sendable
{
  public let relativePath: String
  public let sha256: String
  public let executable: Bool

  public init(relativePath: String, sha256: String, executable: Bool) {
    self.relativePath = relativePath
    self.sha256 = sha256
    self.executable = executable
  }
}

public struct HostPlatformOperatorInterface: Codable, Equatable, Sendable {
  public let bootstrapConfigurationPath: String
  public let bootstrapConfigurationSha256: String
  public let applicationBundlePath: String
  public let applicationBundleRelativePath: String
  public let applicationBundleTreeSha256: String
  public let applicationBundleEntrypointRelativePath: String

  public init(
    bootstrapConfigurationPath: String,
    bootstrapConfigurationSha256: String,
    applicationBundlePath: String,
    applicationBundleRelativePath: String,
    applicationBundleTreeSha256: String,
    applicationBundleEntrypointRelativePath: String
  ) {
    self.bootstrapConfigurationPath = bootstrapConfigurationPath
    self.bootstrapConfigurationSha256 = bootstrapConfigurationSha256
    self.applicationBundlePath = applicationBundlePath
    self.applicationBundleRelativePath = applicationBundleRelativePath
    self.applicationBundleTreeSha256 = applicationBundleTreeSha256
    self.applicationBundleEntrypointRelativePath =
      applicationBundleEntrypointRelativePath
  }
}

public struct HostPlatformRequiredService: Codable, Equatable, Sendable {
  public let role: String
  public let manager: String
  public let name: String
  public let definitionPath: String
  public let definitionSha256: String

  public init(
    role: String,
    manager: String,
    name: String,
    definitionPath: String,
    definitionSha256: String
  ) {
    self.role = role
    self.manager = manager
    self.name = name
    self.definitionPath = definitionPath
    self.definitionSha256 = definitionSha256
  }
}

public struct HostPlatformStableComponent: Codable, Equatable, Sendable {
  public let role: String
  public let executablePath: String
  public let serviceName: String?

  public init(role: String, executablePath: String, serviceName: String?) {
    self.role = role
    self.executablePath = executablePath
    self.serviceName = serviceName
  }
}

public struct HostPlatformMutableStore: Codable, Equatable, Sendable {
  public let id: String
  public let path: String
  public let kind: String
  public let owner: String
  public let retention: String

  public init(id: String, path: String, kind: String, owner: String, retention: String) {
    self.id = id
    self.path = path
    self.kind = kind
    self.owner = owner
    self.retention = retention
  }
}
