import Application
import Contracts
import Domain
import Errors

public enum HostPlatformInstallationManagementError:
  Error,
  Equatable,
  Sendable
{
  case activeInstallationMissing
  case activeInstallationReadFailed(String)
  case operationReadFailed(String)
  case operationAlreadyFailed(String)
  case stagingFailed(String)
  case manifestLoadFailed(String)
  case topologyMismatch(String)
  case activeReleaseNotProven(String)
  case reconciliationFailed(String)
  case compensationFailed(String)
}

extension HostPlatformInstallationManagementError:
  HostPlatformReconciliationFailure
{
  public var reconciliationReason: String {
    switch self {
    case .activeInstallationMissing:
      return "active installation is missing"
    case .activeInstallationReadFailed(let reason):
      return "active installation read failed \(reason)"
    case .operationReadFailed(let reason):
      return "operation read failed \(reason)"
    case .operationAlreadyFailed(let reason):
      return "operation already failed \(reason)"
    case .stagingFailed(let reason):
      return "candidate staging failed \(reason)"
    case .manifestLoadFailed(let reason):
      return "release manifest load failed \(reason)"
    case .topologyMismatch(let reason):
      return "topology mismatch \(reason)"
    case .activeReleaseNotProven(let reason):
      return "active release not proven \(reason)"
    case .reconciliationFailed(let reason):
      return "reconciliation failed \(reason)"
    case .compensationFailed(let reason):
      return "compensation failed \(reason)"
    }
  }
}

/// A compensation effect failed and recording its terminal failure also hit a
/// persistence failure. Both the original compensation error and the real
/// persistence error are preserved so neither is hidden or relabeled, and the
/// durable `.compensating` state remains for resume to retry idempotently.
public struct HostPlatformCompensationPersistenceFailure:
  Error,
  @unchecked Sendable
{
  public let compensation: any Error
  public let persistence: any Error

  public init(compensation: any Error, persistence: any Error) {
    self.compensation = compensation
    self.persistence = persistence
  }
}

public struct RegisterHostPlatformInstallationWorkflow: Sendable {
  private let repository: any HostPlatformInstallationRepository

  public init(repository: any HostPlatformInstallationRepository) {
    self.repository = repository
  }

  public func execute(
    installationId: String,
    activeRelease: HostPlatformRelease,
    operationId: String,
    activatedAt: String
  ) throws -> HostPlatformInstallationManifest {
    let manifest = try HostPlatformInstallationPolicy.makeInitialManifest(
      installationId: installationId,
      activeRelease: activeRelease,
      operationId: operationId,
      activatedAt: activatedAt
    )
    try repository.initializeInstallation(manifest)
    return manifest
  }
}

public struct ManageHostPlatformInstallationWorkflow: Sendable {
  private let repository: any HostPlatformInstallationRepository
  private let candidateStager: any HostPlatformCandidateStaging
  private let reconciler: any HostPlatformReleaseReconciling
  private let observedAt: @Sendable () -> String

  public init(
    repository: any HostPlatformInstallationRepository,
    candidateStager: any HostPlatformCandidateStaging,
    reconciler: any HostPlatformReleaseReconciling,
    observedAt: @escaping @Sendable () -> String
  ) {
    self.repository = repository
    self.candidateStager = candidateStager
    self.reconciler = reconciler
    self.observedAt = observedAt
  }

  public func execute(
    command: HostPlatformInstallationCommand
  ) throws -> HostPlatformInstallationOperation {
    var operation = try loadOrBegin(command: command)

    if operation.phase == .completed {
      return operation
    }
    if operation.phase == .failed {
      throw HostPlatformInstallationManagementError
        .operationAlreadyFailed(operation.failureReason ?? "missing failure reason")
    }
    if operation.phase == .compensated {
      let reason = operation.failureReason ?? "compensation completed"
      operation = try fail(
        operation: operation,
        reason: reason,
        updatedAt: observedAt()
      )
      throw HostPlatformInstallationManagementError.operationAlreadyFailed(
        reason
      )
    }

    if operation.phase == .requested {
      switch candidateStager.stageCandidate(command: command) {
      case .staged(let candidate):
        let next = try HostPlatformInstallationPolicy.recordStagedCandidate(
          operation: operation,
          candidate: candidate,
          updatedAt: candidate.stagedAt
        )
        operation = try save(
          next,
          expectedOperationRevision: operation.operationRevision
        )
      case .failed(let reason):
        operation = try fail(
          operation: operation,
          reason: "candidate staging failed: \(reason)",
          updatedAt: observedAt()
        )
        throw HostPlatformInstallationManagementError.stagingFailed(reason)
      }
    }

    let previous: HostPlatformReleaseArchiveManifest
    let target: HostPlatformReleaseArchiveManifest
    do {
      previous = try loadManifest(
        operation.previousRelease,
        installationId: command.installationId
      )
      target = try loadManifest(
        command.targetRelease,
        installationId: command.installationId
      )
    } catch {
      throw try requirePreReconcile(operation: &operation, error: error)
    }
    do {
      try reconciler.verifyTopology(previous: previous, target: target)
    } catch {
      throw try requirePreReconcile(
        operation: &operation,
        error: HostPlatformInstallationManagementError.topologyMismatch(
          describe(error)
        )
      )
    }

    while true {
      if operation.phase == .compensating {
        try resumeCompensation(
          operation: operation,
          previous: previous,
          target: target
        )
      }
      let result: AdvanceHostPlatformInstallationResult
      do {
        result = try AdvanceHostPlatformInstallationUseCase().advance(
          operation: operation,
          previous: previous,
          target: target,
          reconciler: reconciler,
          observedAt: observedAt
        )
      } catch let error as HostPlatformInstallationPolicyError {
        throw mapPolicy(error)
      } catch let error as AdvanceHostPlatformInstallationError {
        throw HostPlatformInstallationManagementError.reconciliationFailed(
          describe(error)
        )
      } catch {
        try compensateAndFail(
          operation: operation,
          error: error,
          previous: previous,
          target: target
        )
      }
      switch result {
      case .advanced(let next):
        operation = try save(
          next,
          expectedOperationRevision: operation.operationRevision
        )
      case .settle(let settled, let manifest):
        try repository.settleSucceededOperation(
          settled,
          activeManifest: manifest,
          expectedOperationRevision: operation.operationRevision,
          expectedInstallationRevision: operation.expectedInstallationRevision
        )
        return settled
      case .terminal:
        return operation
      }
    }
  }

  private func loadOrBegin(
    command: HostPlatformInstallationCommand
  ) throws -> HostPlatformInstallationOperation {
    switch repository.loadOperation(id: command.operationId) {
    case .loaded(let operation):
      try HostPlatformInstallationPolicy.validate(
        resumed: operation,
        command: command
      )
      return operation
    case .failed(let reason):
      throw HostPlatformInstallationManagementError.operationReadFailed(reason)
    case .missing:
      let manifest: HostPlatformInstallationManifest
      switch repository.loadActiveInstallation() {
      case .loaded(let value):
        manifest = value
      case .missing:
        throw HostPlatformInstallationManagementError
          .activeInstallationMissing
      case .failed(let reason):
        throw HostPlatformInstallationManagementError
          .activeInstallationReadFailed(reason)
      }
      let operation = try HostPlatformInstallationPolicy
        .makeRequestedOperation(command: command, activeManifest: manifest)
      try repository.beginOperation(operation)
      return operation
    }
  }

  private func loadManifest(
    _ release: HostPlatformRelease,
    installationId: String
  ) throws -> HostPlatformReleaseArchiveManifest {
    switch reconciler.loadReleaseManifest(
      release,
      installationId: installationId
    ) {
    case .loaded(let manifest):
      return manifest
    case .failed(let reason):
      throw HostPlatformInstallationManagementError.manifestLoadFailed(reason)
    }
  }

  /// Terminalizes a permanent failure that happens before any irreversible
  /// effect. At `.prepared` only staging has completed and is safe to leave, so
  /// there is nothing to compensate and the operation must not stay active and
  /// stuck. Irreversible phases return the error unchanged and are owned by the
  /// compensation path instead.
  private func requirePreReconcile(
    operation: inout HostPlatformInstallationOperation,
    error: Error
  ) throws -> Error {
    guard operation.phase == .prepared else {
      return error
    }
    let reason = describe(error)
    _ = try fail(
      operation: operation,
      reason: "pre-reconcile proof failed: \(reason)",
      updatedAt: observedAt()
    )
    return error
  }

  private func compensateAndFail(
    operation: HostPlatformInstallationOperation,
    error: Error,
    previous: HostPlatformReleaseArchiveManifest,
    target: HostPlatformReleaseArchiveManifest
  ) throws -> Never {
    let reason = describe(error)
    var current = try save(
      HostPlatformInstallationPolicy.recordCompensating(
        operation: operation,
        reason: reason,
        updatedAt: observedAt()
      ),
      expectedOperationRevision: operation.operationRevision
    )
    // Compensation effect is isolated from persistence so that a persistence
    // failure after a successful effect is never misrecorded as "compensation
    // failed": it propagates as the real persistence failure and leaves the
    // durable .compensating state for resume to retry idempotently.
    do {
      try performCompensation(previous: previous, target: target)
    } catch let compensation {
      let compensationReason = describe(compensation)
      do {
        _ = try fail(
          operation: current,
          reason: "compensation failed: \(compensationReason)",
          updatedAt: observedAt()
        )
      } catch let persistence {
        throw HostPlatformCompensationPersistenceFailure(
          compensation: compensation,
          persistence: persistence
        )
      }
      throw HostPlatformInstallationManagementError.compensationFailed(
        "\(compensationReason) during compensation of \(reason)"
      )
    }
    current = try save(
      HostPlatformInstallationPolicy.recordCompensated(
        operation: current,
        updatedAt: observedAt()
      ),
      expectedOperationRevision: current.operationRevision
    )
    _ = try fail(
      operation: current,
      reason: reason,
      updatedAt: observedAt()
    )
    throw HostPlatformInstallationManagementError.reconciliationFailed(
      "\(reason); previous release restored"
    )
  }

  private func resumeCompensation(
    operation: HostPlatformInstallationOperation,
    previous: HostPlatformReleaseArchiveManifest,
    target: HostPlatformReleaseArchiveManifest
  ) throws -> Never {
    do {
      try performCompensation(previous: previous, target: target)
    } catch let compensation {
      let compensationReason = describe(compensation)
      do {
        _ = try fail(
          operation: operation,
          reason: "compensation failed: \(compensationReason)",
          updatedAt: observedAt()
        )
      } catch let persistence {
        throw HostPlatformCompensationPersistenceFailure(
          compensation: compensation,
          persistence: persistence
        )
      }
      throw HostPlatformInstallationManagementError.compensationFailed(
        compensationReason
      )
    }
    let compensated = try save(
      HostPlatformInstallationPolicy.recordCompensated(
        operation: operation,
        updatedAt: observedAt()
      ),
      expectedOperationRevision: operation.operationRevision
    )
    let reason = compensated.failureReason ?? "compensation completed"
    _ = try fail(
      operation: compensated,
      reason: reason,
      updatedAt: observedAt()
    )
    throw HostPlatformInstallationManagementError.operationAlreadyFailed(
      reason
    )
  }

  private func performCompensation(
    previous: HostPlatformReleaseArchiveManifest,
    target: HostPlatformReleaseArchiveManifest
  ) throws {
    _ = try reconciler.quiesceServices(target.replaceableServices)
    try reconciler.publishInterfaces(previous)
    _ = try reconciler.activateTarget(previous)
    _ = try reconciler.loadServices(previous.replaceableServices)
  }

  private func save(
    _ operation: HostPlatformInstallationOperation,
    expectedOperationRevision: Int
  ) throws -> HostPlatformInstallationOperation {
    try repository.saveOperation(
      operation,
      expectedOperationRevision: expectedOperationRevision
    )
    return operation
  }

  private func fail(
    operation: HostPlatformInstallationOperation,
    reason: String,
    updatedAt: String
  ) throws -> HostPlatformInstallationOperation {
    let failed = try HostPlatformInstallationPolicy.recordFailure(
      operation: operation,
      reason: reason,
      updatedAt: updatedAt
    )
    try repository.settleFailedOperation(
      failed,
      expectedOperationRevision: operation.operationRevision
    )
    return failed
  }

  private func mapPolicy(
    _ error: HostPlatformInstallationPolicyError
  ) -> HostPlatformInstallationManagementError {
    switch error {
    case .activeReleaseNotProven(let reason):
      return .activeReleaseNotProven(reason)
    case .invalidTransition(_, let event):
      return .reconciliationFailed(
        "invalid reconciliation transition event=\(event)"
      )
    default:
      return .reconciliationFailed(describe(error))
    }
  }

  private func describe(_ error: Error) -> String {
    HostPlatformReconciliationFailureDescription.describe(error)
  }
}
