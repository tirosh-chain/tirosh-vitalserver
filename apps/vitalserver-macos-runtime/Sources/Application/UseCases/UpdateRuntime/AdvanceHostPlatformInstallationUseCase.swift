import Contracts
import Domain

public enum AdvanceHostPlatformInstallationResult: Equatable, Sendable {
  case advanced(HostPlatformInstallationOperation)
  case settle(HostPlatformInstallationOperation, HostPlatformInstallationManifest)
  case terminal
}

public enum AdvanceHostPlatformInstallationError: Error, Equatable, Sendable {
  case stagingAlreadyCompleted
  case compensationRequired
}

extension AdvanceHostPlatformInstallationError:
  HostPlatformReconciliationFailure
{
  public var reconciliationReason: String {
    switch self {
    case .stagingAlreadyCompleted:
      return "staging was already completed"
    case .compensationRequired:
      return "compensation is required before reconciliation"
    }
  }
}

/// Interprets the reconciliation step decided by the Domain policy and executes
/// exactly one effect through the reconciler port, recording the durable journal
/// entry. The Workflow owns sequencing, persistence, and compensation; it must
/// not interpret reconciliation steps itself.
public struct AdvanceHostPlatformInstallationUseCase {
  public init() {}

  public func advance(
    operation: HostPlatformInstallationOperation,
    previous: HostPlatformReleaseArchiveManifest,
    target: HostPlatformReleaseArchiveManifest,
    reconciler: any HostPlatformReleaseReconciling,
    observedAt: @Sendable () -> String
  ) throws -> AdvanceHostPlatformInstallationResult {
    let currentTarget = reconciler.readCurrentReleaseTarget()
    let step = try HostPlatformInstallationPolicy.nextStep(
      operation: operation,
      currentReleaseTarget: currentTarget,
      previousReleaseRoot: previous.releaseRootPath,
      targetReleaseRoot: target.releaseRootPath
    )
    switch step {
    case .stageCandidate:
      throw AdvanceHostPlatformInstallationError.stagingAlreadyCompleted
    case .quiescePrevious:
      let observations = try reconciler.quiesceServices(
        previous.replaceableServices
      )
      let next = try HostPlatformInstallationPolicy.recordQuiescePrevious(
        operation: operation,
        observations: observations,
        updatedAt: observedAt()
      )
      return .advanced(next)
    case .publishInterfaces:
      try reconciler.publishInterfaces(target)
      let next = try HostPlatformInstallationPolicy.recordPublishInterfaces(
        operation: operation,
        updatedAt: observedAt()
      )
      return .advanced(next)
    case .activateTarget:
      let resolved = try reconciler.activateTarget(target)
      let next = try HostPlatformInstallationPolicy.recordActivateTarget(
        operation: operation,
        resolvedTarget: resolved,
        updatedAt: observedAt()
      )
      return .advanced(next)
    case .loadTargetServices:
      let observations = try reconciler.loadServices(
        target.replaceableServices
      )
      let next = try HostPlatformInstallationPolicy.recordLoadTargetServices(
        operation: operation,
        observations: observations,
        updatedAt: observedAt()
      )
      return .advanced(next)
    case .settle:
      let settlement = try HostPlatformInstallationPolicy
        .makeCompletedSettlement(operation: operation, settledAt: observedAt())
      return .settle(settlement.operation, settlement.manifest)
    case .compensate:
      throw AdvanceHostPlatformInstallationError.compensationRequired
    case .none:
      return .terminal
    }
  }
}
