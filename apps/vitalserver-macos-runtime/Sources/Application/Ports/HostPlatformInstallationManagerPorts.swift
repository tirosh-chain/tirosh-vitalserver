import Contracts

public enum HostPlatformInstallationManifestReadResult: Equatable, Sendable {
  case missing
  case loaded(HostPlatformInstallationManifest)
  case failed(reason: String)
}

public enum HostPlatformInstallationOperationReadResult: Equatable, Sendable {
  case missing
  case loaded(HostPlatformInstallationOperation)
  case failed(reason: String)
}

public protocol HostPlatformInstallationRepository: Sendable {
  func initializeInstallation(
    _ manifest: HostPlatformInstallationManifest
  ) throws

  func loadActiveInstallation()
    -> HostPlatformInstallationManifestReadResult

  func loadOperation(
    id: String
  ) -> HostPlatformInstallationOperationReadResult

  func beginOperation(
    _ operation: HostPlatformInstallationOperation
  ) throws

  func saveOperation(
    _ operation: HostPlatformInstallationOperation,
    expectedOperationRevision: Int
  ) throws

  func settleSucceededOperation(
    _ operation: HostPlatformInstallationOperation,
    activeManifest: HostPlatformInstallationManifest,
    expectedOperationRevision: Int,
    expectedInstallationRevision: Int
  ) throws

  func settleFailedOperation(
    _ operation: HostPlatformInstallationOperation,
    expectedOperationRevision: Int
  ) throws
}

public enum HostPlatformCandidateStagingResult: Equatable, Sendable {
  case staged(HostPlatformStagedCandidate)
  case failed(reason: String)
}

public protocol HostPlatformCandidateStaging: Sendable {
  func stageCandidate(
    command: HostPlatformInstallationCommand
  ) -> HostPlatformCandidateStagingResult
}

public enum HostPlatformServiceReconciliationResult: Equatable, Sendable {
  case completed(HostPlatformServiceReconciliationReceipt)
  case unavailable(reason: String)
  case failed(reason: String)
}

public protocol HostPlatformServiceReconciling: Sendable {
  func reconcileServices(
    request: HostPlatformServiceReconciliationRequest
  ) -> HostPlatformServiceReconciliationResult
}
