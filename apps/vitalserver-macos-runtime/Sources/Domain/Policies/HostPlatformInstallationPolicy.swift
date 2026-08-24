import Contracts

public enum HostPlatformInstallationPolicyError: Error, Equatable, Sendable {
  case invalidField(String)
  case invalidInstallationRevision(Int)
  case installationIdentityMismatch(expected: String, actual: String)
  case installationRevisionMismatch(expected: Int, actual: Int)
  case targetIsAlreadyActive
  case rollbackReleaseUnavailable
  case rollbackTargetMismatch
  case operationCommandMismatch
  case invalidOperationShape(HostPlatformInstallationPhase)
  case invalidJournal(String)
  case invalidTransition(
    from: HostPlatformInstallationPhase,
    event: String
  )
  case activeReleaseNotProven(String)
  case invalidServiceObservation(String)
}

/// The next irreversible effect a reconciliation workflow must execute.
public enum HostPlatformReconciliationStep: Equatable, Sendable {
  case stageCandidate
  case quiescePrevious
  case publishInterfaces
  case activateTarget
  case loadTargetServices
  case settle
  case compensate
  case none
}

public enum HostPlatformInstallationPolicy {
  public static let schemaVersion =
    HostPlatformInstallationContract.manifestSchemaVersion
  public static let operationSchemaVersion =
    HostPlatformInstallationContract.operationSchemaVersion

  public static func makeInitialManifest(
    installationId: String,
    activeRelease: HostPlatformRelease,
    operationId: String,
    activatedAt: String
  ) throws -> HostPlatformInstallationManifest {
    let manifest = HostPlatformInstallationManifest(
      schemaVersion: schemaVersion,
      installationId: installationId,
      installationRevision: 1,
      activeRelease: activeRelease,
      rollbackRelease: nil,
      activationOperationId: operationId,
      activatedAt: activatedAt
    )
    try validate(manifest)
    return manifest
  }

  public static func makeRequestedOperation(
    command: HostPlatformInstallationCommand,
    activeManifest: HostPlatformInstallationManifest
  ) throws -> HostPlatformInstallationOperation {
    try validate(command: command)
    try validate(activeManifest)
    guard command.installationId == activeManifest.installationId else {
      throw HostPlatformInstallationPolicyError.installationIdentityMismatch(
        expected: command.installationId,
        actual: activeManifest.installationId
      )
    }
    guard command.expectedInstallationRevision == activeManifest.installationRevision else {
      throw HostPlatformInstallationPolicyError.installationRevisionMismatch(
        expected: command.expectedInstallationRevision,
        actual: activeManifest.installationRevision
      )
    }
    guard command.targetRelease != activeManifest.activeRelease else {
      throw HostPlatformInstallationPolicyError.targetIsAlreadyActive
    }
    if command.kind == .rollback {
      guard let rollbackRelease = activeManifest.rollbackRelease else {
        throw HostPlatformInstallationPolicyError.rollbackReleaseUnavailable
      }
      guard rollbackRelease == command.targetRelease else {
        throw HostPlatformInstallationPolicyError.rollbackTargetMismatch
      }
    }
    let operation = HostPlatformInstallationOperation(
      schemaVersion: operationSchemaVersion,
      id: command.operationId,
      operationRevision: 1,
      kind: command.kind,
      phase: .requested,
      installationId: command.installationId,
      expectedInstallationRevision: command.expectedInstallationRevision,
      targetRelease: command.targetRelease,
      previousRelease: activeManifest.activeRelease,
      candidate: nil,
      journal: [],
      failureReason: nil,
      requestedAt: command.requestedAt,
      updatedAt: command.requestedAt
    )
    try validate(operation)
    return operation
  }

  /// Decides the next irreversible effect from the durable phase and the
  /// Host-owned `current` symlink observation. Never advances from missing,
  /// failed, or unknown state without an explicit transition.
  public static func nextStep(
    operation: HostPlatformInstallationOperation,
    currentReleaseTarget: HostPlatformCurrentReleaseTargetRead,
    previousReleaseRoot: String,
    targetReleaseRoot: String
  ) throws -> HostPlatformReconciliationStep {
    try validate(operation)
    switch operation.phase {
    case .requested:
      return .stageCandidate
    case .prepared:
      switch currentReleaseTarget {
      case .resolved(let path) where path == previousReleaseRoot:
        return .quiescePrevious
      case .resolved(let path) where path == targetReleaseRoot:
        // Deep resume: activation already happened in a prior attempt.
        return .activateTarget
      case .resolved(let path):
        throw HostPlatformInstallationPolicyError.activeReleaseNotProven(
          "current target is neither previous nor target actual=\(path)"
        )
      case .notSymlink:
        throw HostPlatformInstallationPolicyError.activeReleaseNotProven(
          "current release link is not a symlink"
        )
      case .missing:
        throw HostPlatformInstallationPolicyError.activeReleaseNotProven(
          "current release link is missing"
        )
      case .readFailed(let reason):
        throw HostPlatformInstallationPolicyError.activeReleaseNotProven(
          "current release link read failed reason=\(reason)"
        )
      }
    case .previousQuiesced:
      return .publishInterfaces
    case .interfacesPublished:
      return .activateTarget
    case .targetActivated:
      return .loadTargetServices
    case .targetServicesLoaded:
      return .settle
    case .compensating:
      return .compensate
    case .compensated, .completed, .failed:
      return .none
    }
  }

  public static func validate(
    command: HostPlatformInstallationCommand
  ) throws {
    try requireIdentifier(command.operationId, field: "operationId")
    try requireIdentifier(command.installationId, field: "installationId")
    try requirePositive(
      command.expectedInstallationRevision,
      field: "expectedInstallationRevision"
    )
    try validate(command.targetRelease)
    guard command.sourceArtifactPath.hasPrefix("/") else {
      throw HostPlatformInstallationPolicyError.invalidField(
        "sourceArtifactPath"
      )
    }
    try requireIdentifier(command.stagingAttemptId, field: "stagingAttemptId")
    try requireTimestamp(command.requestedAt, field: "requestedAt")
  }

  public static func validate(
    _ manifest: HostPlatformInstallationManifest
  ) throws {
    guard manifest.schemaVersion == schemaVersion else {
      throw HostPlatformInstallationPolicyError.invalidField("schemaVersion")
    }
    try requireIdentifier(manifest.installationId, field: "installationId")
    try requirePositive(
      manifest.installationRevision,
      field: "installationRevision"
    )
    try validate(manifest.activeRelease)
    if let rollbackRelease = manifest.rollbackRelease {
      try validate(rollbackRelease)
      guard rollbackRelease != manifest.activeRelease else {
        throw HostPlatformInstallationPolicyError.invalidField(
          "rollbackRelease"
        )
      }
    }
    try requireIdentifier(
      manifest.activationOperationId,
      field: "activationOperationId"
    )
    try requireTimestamp(manifest.activatedAt, field: "activatedAt")
  }

  public static func validate(
    _ operation: HostPlatformInstallationOperation
  ) throws {
    guard operation.schemaVersion == operationSchemaVersion else {
      throw HostPlatformInstallationPolicyError.invalidField("schemaVersion")
    }
    try requireIdentifier(operation.id, field: "id")
    try requirePositive(operation.operationRevision, field: "operationRevision")
    try requireIdentifier(operation.installationId, field: "installationId")
    try requirePositive(
      operation.expectedInstallationRevision,
      field: "expectedInstallationRevision"
    )
    try validate(operation.targetRelease)
    try validate(operation.previousRelease)
    try requireTimestamp(operation.requestedAt, field: "requestedAt")
    try requireTimestamp(operation.updatedAt, field: "updatedAt")

    switch operation.phase {
    case .requested:
      guard operation.candidate == nil,
        operation.journal.isEmpty,
        operation.failureReason == nil
      else {
        throw HostPlatformInstallationPolicyError.invalidOperationShape(
          operation.phase
        )
      }
    case .prepared, .previousQuiesced, .interfacesPublished,
      .targetActivated, .targetServicesLoaded, .completed:
      guard operation.candidate != nil, operation.failureReason == nil else {
        throw HostPlatformInstallationPolicyError.invalidOperationShape(
          operation.phase
        )
      }
    case .compensating, .compensated:
      guard operation.candidate != nil,
        operation.failureReason?.isEmpty == false
      else {
        throw HostPlatformInstallationPolicyError.invalidOperationShape(
          operation.phase
        )
      }
    case .failed:
      guard operation.failureReason?.isEmpty == false else {
        throw HostPlatformInstallationPolicyError.invalidOperationShape(
          operation.phase
        )
      }
    }
    if let candidate = operation.candidate {
      guard candidate.release == operation.targetRelease else {
        throw HostPlatformInstallationPolicyError.invalidField(
          "candidate.release"
        )
      }
      try requireIdentifier(
        candidate.stagingReceiptId,
        field: "stagingReceiptId"
      )
      try requireTimestamp(candidate.stagedAt, field: "stagedAt")
    }
    try validateJournal(operation.journal, phase: operation.phase)
  }

  public static func validate(
    resumed operation: HostPlatformInstallationOperation,
    command: HostPlatformInstallationCommand
  ) throws {
    try validate(operation)
    try validate(command: command)
    guard operation.id == command.operationId,
      operation.kind == command.kind,
      operation.installationId == command.installationId,
      operation.expectedInstallationRevision == command.expectedInstallationRevision,
      operation.targetRelease == command.targetRelease,
      operation.requestedAt == command.requestedAt
    else {
      throw HostPlatformInstallationPolicyError.operationCommandMismatch
    }
  }

  public static func recordStagedCandidate(
    operation: HostPlatformInstallationOperation,
    candidate: HostPlatformStagedCandidate,
    updatedAt: String
  ) throws -> HostPlatformInstallationOperation {
    try validate(operation)
    guard operation.phase == .requested else {
      throw invalidTransition(operation, event: "prepared")
    }
    guard candidate.release == operation.targetRelease else {
      throw HostPlatformInstallationPolicyError.invalidField(
        "candidate.release"
      )
    }
    let entry = HostPlatformReconciliationJournalEntry(
      effect: .stageCandidate,
      phase: .prepared,
      currentReleaseTarget: nil,
      services: [],
      observedAt: updatedAt
    )
    let next = replacing(
      operation,
      phase: .prepared,
      candidate: candidate,
      appendedEntry: entry,
      failureReason: nil,
      updatedAt: updatedAt
    )
    try validate(next)
    return next
  }

  public static func recordQuiescePrevious(
    operation: HostPlatformInstallationOperation,
    observations: [HostPlatformLaunchdServiceObservation],
    updatedAt: String
  ) throws -> HostPlatformInstallationOperation {
    try validate(operation)
    guard operation.phase == .prepared else {
      throw invalidTransition(operation, event: "previous-quiesced")
    }
    let entry = HostPlatformReconciliationJournalEntry(
      effect: .quiescePrevious,
      phase: .previousQuiesced,
      currentReleaseTarget: nil,
      services: observations,
      observedAt: updatedAt
    )
    let next = replacing(
      operation,
      phase: .previousQuiesced,
      candidate: operation.candidate,
      appendedEntry: entry,
      failureReason: nil,
      updatedAt: updatedAt
    )
    try validate(next)
    return next
  }

  public static func recordPublishInterfaces(
    operation: HostPlatformInstallationOperation,
    updatedAt: String
  ) throws -> HostPlatformInstallationOperation {
    try validate(operation)
    guard operation.phase == .previousQuiesced else {
      throw invalidTransition(operation, event: "interfaces-published")
    }
    let entry = HostPlatformReconciliationJournalEntry(
      effect: .publishInterfaces,
      phase: .interfacesPublished,
      currentReleaseTarget: nil,
      services: [],
      observedAt: updatedAt
    )
    let next = replacing(
      operation,
      phase: .interfacesPublished,
      candidate: operation.candidate,
      appendedEntry: entry,
      failureReason: nil,
      updatedAt: updatedAt
    )
    try validate(next)
    return next
  }

  public static func recordActivateTarget(
    operation: HostPlatformInstallationOperation,
    resolvedTarget: String,
    updatedAt: String
  ) throws -> HostPlatformInstallationOperation {
    try validate(operation)
    guard operation.phase == .interfacesPublished
      || operation.phase == .prepared
    else {
      throw invalidTransition(operation, event: "target-activated")
    }
    guard resolvedTarget.hasPrefix("/") else {
      throw HostPlatformInstallationPolicyError.invalidField(
        "resolvedTarget"
      )
    }
    let entry = HostPlatformReconciliationJournalEntry(
      effect: .activateTarget,
      phase: .targetActivated,
      currentReleaseTarget: resolvedTarget,
      services: [],
      observedAt: updatedAt
    )
    let next = replacing(
      operation,
      phase: .targetActivated,
      candidate: operation.candidate,
      appendedEntry: entry,
      failureReason: nil,
      updatedAt: updatedAt
    )
    try validate(next)
    return next
  }

  public static func recordLoadTargetServices(
    operation: HostPlatformInstallationOperation,
    observations: [HostPlatformLaunchdServiceObservation],
    updatedAt: String
  ) throws -> HostPlatformInstallationOperation {
    try validate(operation)
    guard operation.phase == .targetActivated else {
      throw invalidTransition(operation, event: "target-services-loaded")
    }
    let entry = HostPlatformReconciliationJournalEntry(
      effect: .loadTargetServices,
      phase: .targetServicesLoaded,
      currentReleaseTarget: nil,
      services: observations,
      observedAt: updatedAt
    )
    let next = replacing(
      operation,
      phase: .targetServicesLoaded,
      candidate: operation.candidate,
      appendedEntry: entry,
      failureReason: nil,
      updatedAt: updatedAt
    )
    try validate(next)
    return next
  }

  public static func recordCompensating(
    operation: HostPlatformInstallationOperation,
    reason: String,
    updatedAt: String
  ) throws -> HostPlatformInstallationOperation {
    try validate(operation)
    guard !reason.isEmpty else {
      throw HostPlatformInstallationPolicyError.invalidField("reason")
    }
    guard isCompensatable(operation.phase) else {
      throw invalidTransition(operation, event: "compensating")
    }
    let entry = HostPlatformReconciliationJournalEntry(
      effect: .compensate,
      phase: .compensating,
      currentReleaseTarget: nil,
      services: [],
      observedAt: updatedAt
    )
    let next = replacing(
      operation,
      phase: .compensating,
      candidate: operation.candidate,
      appendedEntry: entry,
      failureReason: reason,
      updatedAt: updatedAt
    )
    try validate(next)
    return next
  }

  public static func recordCompensated(
    operation: HostPlatformInstallationOperation,
    updatedAt: String
  ) throws -> HostPlatformInstallationOperation {
    try validate(operation)
    guard operation.phase == .compensating else {
      throw invalidTransition(operation, event: "compensated")
    }
    let entry = HostPlatformReconciliationJournalEntry(
      effect: .compensate,
      phase: .compensated,
      currentReleaseTarget: nil,
      services: [],
      observedAt: updatedAt
    )
    let next = replacing(
      operation,
      phase: .compensated,
      candidate: operation.candidate,
      appendedEntry: entry,
      failureReason: operation.failureReason,
      updatedAt: updatedAt
    )
    try validate(next)
    return next
  }

  public static func recordFailure(
    operation: HostPlatformInstallationOperation,
    reason: String,
    updatedAt: String
  ) throws -> HostPlatformInstallationOperation {
    try validate(operation)
    guard !reason.isEmpty else {
      throw HostPlatformInstallationPolicyError.invalidField("reason")
    }
    guard operation.phase == .requested
      || operation.phase == .prepared
      || operation.phase == .compensating
      || operation.phase == .compensated
    else {
      throw invalidTransition(operation, event: "failed")
    }
    let entry = HostPlatformReconciliationJournalEntry(
      effect: .fail,
      phase: .failed,
      currentReleaseTarget: nil,
      services: [],
      observedAt: updatedAt
    )
    let next = replacing(
      operation,
      phase: .failed,
      candidate: operation.candidate,
      appendedEntry: entry,
      failureReason: reason,
      updatedAt: updatedAt
    )
    try validate(next)
    return next
  }

  public static func makeCompletedSettlement(
    operation: HostPlatformInstallationOperation,
    settledAt: String
  ) throws -> (
    operation: HostPlatformInstallationOperation,
    manifest: HostPlatformInstallationManifest
  ) {
    try validate(operation)
    try requireTimestamp(settledAt, field: "settledAt")
    guard operation.phase == .targetServicesLoaded else {
      throw invalidTransition(operation, event: "settle")
    }
    let entry = HostPlatformReconciliationJournalEntry(
      effect: .settle,
      phase: .completed,
      currentReleaseTarget: nil,
      services: [],
      observedAt: settledAt
    )
    let completed = replacing(
      operation,
      phase: .completed,
      candidate: operation.candidate,
      appendedEntry: entry,
      failureReason: nil,
      updatedAt: settledAt
    )
    let manifest = HostPlatformInstallationManifest(
      schemaVersion: schemaVersion,
      installationId: operation.installationId,
      installationRevision: operation.expectedInstallationRevision + 1,
      activeRelease: operation.targetRelease,
      rollbackRelease: operation.previousRelease,
      activationOperationId: operation.id,
      activatedAt: settledAt
    )
    try validate(completed)
    try validate(manifest)
    return (completed, manifest)
  }

  public static func validatePersistenceTransition(
    previous: HostPlatformInstallationOperation,
    next: HostPlatformInstallationOperation
  ) throws {
    try validate(previous)
    try validate(next)
    guard previous.id == next.id,
      previous.schemaVersion == next.schemaVersion,
      previous.kind == next.kind,
      previous.installationId == next.installationId,
      previous.expectedInstallationRevision
        == next.expectedInstallationRevision,
      previous.targetRelease == next.targetRelease,
      previous.previousRelease == next.previousRelease,
      previous.requestedAt == next.requestedAt,
      next.operationRevision == previous.operationRevision + 1
    else {
      throw HostPlatformInstallationPolicyError.operationCommandMismatch
    }
    let allowed: Bool
    switch (previous.phase, next.phase) {
    case (.requested, .prepared),
      (.requested, .failed),
      (.prepared, .failed),
      (.prepared, .previousQuiesced),
      (.prepared, .targetActivated),
      (.prepared, .compensating),
      (.previousQuiesced, .interfacesPublished),
      (.previousQuiesced, .compensating),
      (.interfacesPublished, .targetActivated),
      (.interfacesPublished, .compensating),
      (.targetActivated, .targetServicesLoaded),
      (.targetActivated, .compensating),
      (.targetServicesLoaded, .completed),
      (.targetServicesLoaded, .compensating),
      (.compensating, .compensated),
      (.compensating, .failed),
      (.compensated, .failed):
      allowed = true
    default:
      allowed = false
    }
    guard allowed else {
      throw HostPlatformInstallationPolicyError.invalidTransition(
        from: previous.phase,
        event: next.phase.rawValue
      )
    }
  }

  private static func isCompensatable(
    _ phase: HostPlatformInstallationPhase
  ) -> Bool {
    switch phase {
    case .prepared, .previousQuiesced, .interfacesPublished,
      .targetActivated, .targetServicesLoaded:
      true
    case .requested, .compensating, .compensated, .completed, .failed:
      false
    }
  }

  private static func validateJournal(
    _ journal: [HostPlatformReconciliationJournalEntry],
    phase: HostPlatformInstallationPhase
  ) throws {
    if journal.isEmpty {
      guard phase == .requested else {
        throw HostPlatformInstallationPolicyError.invalidJournal(
          "empty journal requires requested phase"
        )
      }
      return
    }
    guard journal.last?.phase == phase else {
      throw HostPlatformInstallationPolicyError.invalidJournal(
        "last journal phase does not match operation phase"
      )
    }
    for entry in journal {
      switch (entry.effect, entry.phase) {
      case (.stageCandidate, .prepared):
        break
      case (.quiescePrevious, .previousQuiesced):
        break
      case (.publishInterfaces, .interfacesPublished):
        break
      case (.activateTarget, .targetActivated):
        guard entry.currentReleaseTarget?.hasPrefix("/") == true else {
          throw HostPlatformInstallationPolicyError.invalidJournal(
            "activateTarget entry is missing the resolved target"
          )
        }
      case (.loadTargetServices, .targetServicesLoaded):
        break
      case (.compensate, .compensating),
        (.compensate, .compensated):
        break
      case (.settle, .completed):
        break
      case (.fail, .failed):
        break
      default:
        throw HostPlatformInstallationPolicyError.invalidJournal(
          "effect \(entry.effect.rawValue) does not match phase \(entry.phase.rawValue)"
        )
      }
      guard !entry.observedAt.isEmpty else {
        throw HostPlatformInstallationPolicyError.invalidJournal(
          "journal entry is missing observedAt"
        )
      }
    }
  }

  private static func validate(_ release: HostPlatformRelease) throws {
    try requireIdentifier(release.id, field: "release.id")
    guard !release.version.isEmpty, release.version.count <= 128 else {
      throw HostPlatformInstallationPolicyError.invalidField(
        "release.version"
      )
    }
    guard release.sha256.count == 64,
      release.sha256.allSatisfy({
        $0.isNumber || ("a"..."f").contains(String($0))
      })
    else {
      throw HostPlatformInstallationPolicyError.invalidField(
        "release.sha256"
      )
    }
    let parts = release.slotRelativePath.split(
      separator: "/",
      omittingEmptySubsequences: false
    )
    guard !release.slotRelativePath.hasPrefix("/"),
      !release.slotRelativePath.contains("\\"),
      !parts.isEmpty,
      !parts.contains(where: {
        $0.isEmpty || $0 == "." || $0 == ".."
      })
    else {
      throw HostPlatformInstallationPolicyError.invalidField(
        "release.slotRelativePath"
      )
    }
  }

  private static func replacing(
    _ operation: HostPlatformInstallationOperation,
    phase: HostPlatformInstallationPhase,
    candidate: HostPlatformStagedCandidate?,
    appendedEntry: HostPlatformReconciliationJournalEntry,
    failureReason: String?,
    updatedAt: String
  ) -> HostPlatformInstallationOperation {
    HostPlatformInstallationOperation(
      schemaVersion: operation.schemaVersion,
      id: operation.id,
      operationRevision: operation.operationRevision + 1,
      kind: operation.kind,
      phase: phase,
      installationId: operation.installationId,
      expectedInstallationRevision: operation.expectedInstallationRevision,
      targetRelease: operation.targetRelease,
      previousRelease: operation.previousRelease,
      candidate: candidate,
      journal: operation.journal + [appendedEntry],
      failureReason: failureReason,
      requestedAt: operation.requestedAt,
      updatedAt: updatedAt
    )
  }

  private static func invalidTransition(
    _ operation: HostPlatformInstallationOperation,
    event: String
  ) -> HostPlatformInstallationPolicyError {
    .invalidTransition(from: operation.phase, event: event)
  }

  private static func requireIdentifier(
    _ value: String,
    field: String
  ) throws {
    guard UpdateBootstrapIdentifierSyntax.isIdentifier(value) else {
      throw HostPlatformInstallationPolicyError.invalidField(field)
    }
  }

  private static func requirePositive(_ value: Int, field: String) throws {
    guard value > 0 else {
      throw
        HostPlatformInstallationPolicyError
        .invalidInstallationRevision(value)
    }
  }

  private static func requireTimestamp(_ value: String, field: String) throws {
    guard !value.isEmpty else {
      throw HostPlatformInstallationPolicyError.invalidField(field)
    }
  }
}

extension HostPlatformInstallationPolicyError:
  HostPlatformReconciliationFailure
{
  public var reconciliationReason: String {
    switch self {
    case .invalidField(let field):
      return "invalid field \(field)"
    case .invalidInstallationRevision(let value):
      return "invalid installation revision \(value)"
    case .installationIdentityMismatch(let expected, let actual):
      return "installation identity mismatch expected=\(expected) actual=\(actual)"
    case .installationRevisionMismatch(let expected, let actual):
      return "installation revision mismatch expected=\(expected) actual=\(actual)"
    case .targetIsAlreadyActive:
      return "target is already active"
    case .rollbackReleaseUnavailable:
      return "rollback release is unavailable"
    case .rollbackTargetMismatch:
      return "rollback target mismatch"
    case .operationCommandMismatch:
      return "operation command mismatch"
    case .invalidOperationShape(let phase):
      return "invalid operation shape phase=\(phase.rawValue)"
    case .invalidJournal(let reason):
      return "invalid journal \(reason)"
    case .invalidTransition(let from, let event):
      return "invalid transition from=\(from.rawValue) event=\(event)"
    case .activeReleaseNotProven(let reason):
      return "active release not proven \(reason)"
    case .invalidServiceObservation(let reason):
      return "invalid service observation \(reason)"
    }
  }
}
