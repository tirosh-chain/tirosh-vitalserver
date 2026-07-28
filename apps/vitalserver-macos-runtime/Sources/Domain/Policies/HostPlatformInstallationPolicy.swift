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
  case invalidOperationShape(HostPlatformInstallationOperationState)
  case invalidTransition(
    from: HostPlatformInstallationOperationState,
    event: String
  )
  case invalidServiceReceipt
}

public enum HostPlatformInstallationPolicy {
  public static let schemaVersion = "vitalserver.host-platform-installation/v1"
  public static let operationSchemaVersion =
    "vitalserver.host-platform-installation-operation/v1"
  public static let serviceRequestSchemaVersion =
    "vitalserver.host-platform-service-reconciliation/v1"
  public static let serviceReceiptSchemaVersion =
    "vitalserver.host-platform-service-reconciliation-receipt/v1"

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
      state: .requested,
      installationId: command.installationId,
      expectedInstallationRevision: command.expectedInstallationRevision,
      targetRelease: command.targetRelease,
      previousRelease: activeManifest.activeRelease,
      candidate: nil,
      serviceReceipt: nil,
      failureReason: nil,
      requestedAt: command.requestedAt,
      updatedAt: command.requestedAt
    )
    try validate(operation)
    return operation
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

    let validShape: Bool
    switch operation.state {
    case .requested:
      validShape =
        operation.candidate == nil
        && operation.serviceReceipt == nil
        && operation.failureReason == nil
    case .candidateStaged:
      validShape =
        operation.candidate != nil
        && operation.serviceReceipt == nil
        && operation.failureReason == nil
    case .servicesReconciled, .succeeded:
      validShape =
        operation.candidate != nil
        && operation.serviceReceipt?.outcome == .succeeded
        && operation.failureReason == nil
    case .failed:
      validShape = operation.failureReason?.isEmpty == false
    }
    guard validShape else {
      throw HostPlatformInstallationPolicyError.invalidOperationShape(
        operation.state
      )
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
    if let receipt = operation.serviceReceipt {
      try validate(receipt, for: operation)
    }
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
    guard operation.state == .requested else {
      throw invalidTransition(operation, event: "candidate-staged")
    }
    guard candidate.release == operation.targetRelease else {
      throw HostPlatformInstallationPolicyError.invalidField(
        "candidate.release"
      )
    }
    let next = replacing(
      operation,
      state: .candidateStaged,
      candidate: candidate,
      serviceReceipt: nil,
      failureReason: nil,
      updatedAt: updatedAt
    )
    try validate(next)
    return next
  }

  public static func serviceRequest(
    for operation: HostPlatformInstallationOperation
  ) throws -> HostPlatformServiceReconciliationRequest {
    try validate(operation)
    guard operation.state == .candidateStaged else {
      throw invalidTransition(operation, event: "reconcile-services")
    }
    return HostPlatformServiceReconciliationRequest(
      schemaVersion: serviceRequestSchemaVersion,
      reconciliationId: "\(operation.id).services",
      operationId: operation.id,
      installationId: operation.installationId,
      expectedInstallationRevision: operation.expectedInstallationRevision,
      targetRelease: operation.targetRelease
    )
  }

  public static func recordServiceReconciliation(
    operation: HostPlatformInstallationOperation,
    receipt: HostPlatformServiceReconciliationReceipt
  ) throws -> HostPlatformInstallationOperation {
    guard operation.state == .candidateStaged else {
      throw invalidTransition(operation, event: "services-reconciled")
    }
    try validate(receipt, for: operation)
    guard receipt.outcome == .succeeded else {
      throw HostPlatformInstallationPolicyError.invalidServiceReceipt
    }
    let next = replacing(
      operation,
      state: .servicesReconciled,
      candidate: operation.candidate,
      serviceReceipt: receipt,
      failureReason: nil,
      updatedAt: receipt.observedAt
    )
    try validate(next)
    return next
  }

  public static func makeSucceededSettlement(
    operation: HostPlatformInstallationOperation
  ) throws -> (
    operation: HostPlatformInstallationOperation,
    manifest: HostPlatformInstallationManifest
  ) {
    guard operation.state == .servicesReconciled,
      let receipt = operation.serviceReceipt
    else {
      throw invalidTransition(operation, event: "settle-succeeded")
    }
    let succeeded = replacing(
      operation,
      state: .succeeded,
      candidate: operation.candidate,
      serviceReceipt: receipt,
      failureReason: nil,
      updatedAt: receipt.observedAt
    )
    let manifest = HostPlatformInstallationManifest(
      schemaVersion: schemaVersion,
      installationId: operation.installationId,
      installationRevision: operation.expectedInstallationRevision + 1,
      activeRelease: operation.targetRelease,
      rollbackRelease: operation.previousRelease,
      activationOperationId: operation.id,
      activatedAt: receipt.observedAt
    )
    try validate(succeeded)
    try validate(manifest)
    return (succeeded, manifest)
  }

  public static func recordFailure(
    operation: HostPlatformInstallationOperation,
    reason: String,
    updatedAt: String
  ) throws -> HostPlatformInstallationOperation {
    guard operation.state != .succeeded,
      operation.state != .failed,
      !reason.isEmpty
    else {
      throw invalidTransition(operation, event: "failed")
    }
    let failed = replacing(
      operation,
      state: .failed,
      candidate: operation.candidate,
      serviceReceipt: operation.serviceReceipt,
      failureReason: reason,
      updatedAt: updatedAt
    )
    try validate(failed)
    return failed
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
    switch (previous.state, next.state) {
    case (.requested, .candidateStaged),
      (.candidateStaged, .servicesReconciled),
      (.servicesReconciled, .succeeded),
      (.requested, .failed),
      (.candidateStaged, .failed),
      (.servicesReconciled, .failed):
      allowed = true
    default:
      allowed = false
    }
    guard allowed else {
      throw HostPlatformInstallationPolicyError.invalidTransition(
        from: previous.state,
        event: next.state.rawValue
      )
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

  private static func validate(
    _ receipt: HostPlatformServiceReconciliationReceipt,
    for operation: HostPlatformInstallationOperation
  ) throws {
    guard receipt.schemaVersion == serviceReceiptSchemaVersion,
      receipt.reconciliationId == "\(operation.id).services",
      receipt.operationId == operation.id,
      receipt.installationId == operation.installationId,
      receipt.expectedInstallationRevision == operation.expectedInstallationRevision,
      receipt.targetReleaseId == operation.targetRelease.id,
      receipt.targetReleaseSHA256 == operation.targetRelease.sha256,
      !receipt.observedAt.isEmpty,
      (receipt.outcome == .succeeded) == (receipt.failureReason == nil),
      receipt.outcome == .succeeded
        || receipt.failureReason?.isEmpty == false
    else {
      throw HostPlatformInstallationPolicyError.invalidServiceReceipt
    }
  }

  private static func replacing(
    _ operation: HostPlatformInstallationOperation,
    state: HostPlatformInstallationOperationState,
    candidate: HostPlatformStagedCandidate?,
    serviceReceipt: HostPlatformServiceReconciliationReceipt?,
    failureReason: String?,
    updatedAt: String
  ) -> HostPlatformInstallationOperation {
    HostPlatformInstallationOperation(
      schemaVersion: operation.schemaVersion,
      id: operation.id,
      operationRevision: operation.operationRevision + 1,
      kind: operation.kind,
      state: state,
      installationId: operation.installationId,
      expectedInstallationRevision: operation.expectedInstallationRevision,
      targetRelease: operation.targetRelease,
      previousRelease: operation.previousRelease,
      candidate: candidate,
      serviceReceipt: serviceReceipt,
      failureReason: failureReason,
      requestedAt: operation.requestedAt,
      updatedAt: updatedAt
    )
  }

  private static func invalidTransition(
    _ operation: HostPlatformInstallationOperation,
    event: String
  ) -> HostPlatformInstallationPolicyError {
    .invalidTransition(from: operation.state, event: event)
  }

  private static func requireIdentifier(
    _ value: String,
    field: String
  ) throws {
    guard !value.isEmpty,
      value.count <= 128,
      value.allSatisfy({
        $0.isLetter || $0.isNumber || "-._:".contains($0)
      })
    else {
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
