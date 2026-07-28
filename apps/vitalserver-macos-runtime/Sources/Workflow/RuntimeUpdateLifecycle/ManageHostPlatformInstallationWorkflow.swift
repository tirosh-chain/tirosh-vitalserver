import Application
import Contracts
import Domain

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
  case serviceReconciliationUnavailable(String)
  case serviceReconciliationFailed(String)
  case serviceReconciliationRejected(String)
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
  private let serviceReconciler: any HostPlatformServiceReconciling
  private let failureObservedAt: @Sendable () -> String

  public init(
    repository: any HostPlatformInstallationRepository,
    candidateStager: any HostPlatformCandidateStaging,
    serviceReconciler: any HostPlatformServiceReconciling,
    failureObservedAt: @escaping @Sendable () -> String
  ) {
    self.repository = repository
    self.candidateStager = candidateStager
    self.serviceReconciler = serviceReconciler
    self.failureObservedAt = failureObservedAt
  }

  public func execute(
    command: HostPlatformInstallationCommand
  ) throws -> HostPlatformInstallationOperation {
    var operation = try loadOrBegin(command: command)

    if operation.state == .failed {
      throw
        HostPlatformInstallationManagementError
        .operationAlreadyFailed(operation.failureReason ?? "missing failure reason")
    }
    if operation.state == .succeeded {
      return operation
    }

    if operation.state == .requested {
      switch candidateStager.stageCandidate(command: command) {
      case .staged(let candidate):
        let next =
          try HostPlatformInstallationPolicy
          .recordStagedCandidate(
            operation: operation,
            candidate: candidate,
            updatedAt: candidate.stagedAt
          )
        try repository.saveOperation(
          next,
          expectedOperationRevision: operation.operationRevision
        )
        operation = next
      case .failed(let reason):
        try fail(
          operation: operation,
          reason: "candidate staging failed: \(reason)",
          updatedAt: failureObservedAt()
        )
        throw
          HostPlatformInstallationManagementError
          .stagingFailed(reason)
      }
    }

    if operation.state == .candidateStaged {
      let request = try HostPlatformInstallationPolicy.serviceRequest(
        for: operation
      )
      switch serviceReconciler.reconcileServices(request: request) {
      case .completed(let receipt):
        guard receipt.outcome == .succeeded else {
          let reason =
            receipt.failureReason
            ?? "failed receipt omitted failureReason"
          try fail(
            operation: operation,
            reason: "service reconciliation rejected: \(reason)",
            updatedAt: receipt.observedAt
          )
          throw
            HostPlatformInstallationManagementError
            .serviceReconciliationRejected(reason)
        }
        let next =
          try HostPlatformInstallationPolicy
          .recordServiceReconciliation(
            operation: operation,
            receipt: receipt
          )
        try repository.saveOperation(
          next,
          expectedOperationRevision: operation.operationRevision
        )
        operation = next
      case .unavailable(let reason):
        try fail(
          operation: operation,
          reason: "service reconciler unavailable: \(reason)",
          updatedAt: failureObservedAt()
        )
        throw
          HostPlatformInstallationManagementError
          .serviceReconciliationUnavailable(reason)
      case .failed(let reason):
        try fail(
          operation: operation,
          reason: "service reconciliation failed: \(reason)",
          updatedAt: failureObservedAt()
        )
        throw
          HostPlatformInstallationManagementError
          .serviceReconciliationFailed(reason)
      }
    }

    let settlement =
      try HostPlatformInstallationPolicy
      .makeSucceededSettlement(operation: operation)
    try repository.settleSucceededOperation(
      settlement.operation,
      activeManifest: settlement.manifest,
      expectedOperationRevision: operation.operationRevision,
      expectedInstallationRevision: operation.expectedInstallationRevision
    )
    return settlement.operation
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
      throw
        HostPlatformInstallationManagementError
        .operationReadFailed(reason)
    case .missing:
      let manifest: HostPlatformInstallationManifest
      switch repository.loadActiveInstallation() {
      case .loaded(let value):
        manifest = value
      case .missing:
        throw HostPlatformInstallationManagementError
          .activeInstallationMissing
      case .failed(let reason):
        throw
          HostPlatformInstallationManagementError
          .activeInstallationReadFailed(reason)
      }
      let operation =
        try HostPlatformInstallationPolicy
        .makeRequestedOperation(
          command: command,
          activeManifest: manifest
        )
      try repository.beginOperation(operation)
      return operation
    }
  }

  private func fail(
    operation: HostPlatformInstallationOperation,
    reason: String,
    updatedAt: String
  ) throws {
    let failed = try HostPlatformInstallationPolicy.recordFailure(
      operation: operation,
      reason: reason,
      updatedAt: updatedAt
    )
    try repository.settleFailedOperation(
      failed,
      expectedOperationRevision: operation.operationRevision
    )
  }
}
