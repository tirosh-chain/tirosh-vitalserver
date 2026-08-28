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

public enum HostPlatformReleaseManifestLoadResult: Equatable, Sendable {
  case loaded(HostPlatformReleaseArchiveManifest)
  case failed(reason: String)
}

/// Executes one Host Platform reconciliation effect at a time and reports
/// typed, Host-owned observations. Each effect is idempotent: re-running it
/// after a crash resumes to the same outcome instead of corrupting state.
public protocol HostPlatformReleaseReconciling: Sendable {
  func loadReleaseManifest(
    _ release: HostPlatformRelease,
    installationId: String
  ) -> HostPlatformReleaseManifestLoadResult

  func verifyTopology(
    previous: HostPlatformReleaseArchiveManifest,
    target: HostPlatformReleaseArchiveManifest
  ) throws

  func readCurrentReleaseTarget() -> HostPlatformCurrentReleaseTargetRead

  func readServiceStates(
    _ services: [HostPlatformRequiredService]
  ) -> [HostPlatformLaunchdServiceObservation]

  func quiesceServices(
    _ services: [HostPlatformRequiredService]
  ) throws -> [HostPlatformLaunchdServiceObservation]

  func publishInterfaces(
    _ manifest: HostPlatformReleaseArchiveManifest
  ) throws

  func activateTarget(
    _ manifest: HostPlatformReleaseArchiveManifest
  ) throws -> String

  func loadServices(
    _ services: [HostPlatformRequiredService]
  ) throws -> [HostPlatformLaunchdServiceObservation]
}
