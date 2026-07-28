import Application
import Contracts
import Domain
import Workflow
import XCTest

final class ManageHostPlatformInstallationWorkflowTests: XCTestCase {
  func testExecutePersistsEachExplicitOwnerStateAndSettlesAtomically() throws {
    let repository = HostInstallationRepositorySpy(
      manifest: initialManifest()
    )
    let workflow = ManageHostPlatformInstallationWorkflow(
      repository: repository,
      candidateStager: CandidateStagerStub(result: .staged(candidate())),
      serviceReconciler: ServiceReconcilerStub(
        result: .completed(serviceReceipt())
      ),
      failureObservedAt: { "2026-07-29T01:00:03Z" }
    )

    let result = try workflow.execute(command: command())

    XCTAssertEqual(result.state, .succeeded)
    XCTAssertEqual(
      repository.events,
      [
        "begin:requested:1",
        "save:candidate-staged:2:expected=1",
        "save:services-reconciled:3:expected=2",
        "settle:succeeded:4:expectedOperation=3:expectedInstallation=1",
      ]
    )
    XCTAssertEqual(
      repository.manifest?.activeRelease.id,
      "host-0.2.2"
    )
  }

  func testResumeFromStagedStateDoesNotStageAgain() throws {
    let repository = HostInstallationRepositorySpy(
      manifest: initialManifest()
    )
    let staged = try stagedOperation()
    repository.operations[staged.id] = staged
    let stager = CandidateStagerStub(result: .failed(reason: "must not run"))
    let workflow = ManageHostPlatformInstallationWorkflow(
      repository: repository,
      candidateStager: stager,
      serviceReconciler: ServiceReconcilerStub(
        result: .completed(serviceReceipt())
      ),
      failureObservedAt: { "2026-07-29T01:00:03Z" }
    )

    let result = try workflow.execute(command: command())

    XCTAssertEqual(result.state, .succeeded)
    XCTAssertEqual(stager.callCount, 0)
  }

  func testMissingServiceReceiptCannotBecomeSuccess() throws {
    let repository = HostInstallationRepositorySpy(
      manifest: initialManifest()
    )
    let workflow = ManageHostPlatformInstallationWorkflow(
      repository: repository,
      candidateStager: CandidateStagerStub(result: .staged(candidate())),
      serviceReconciler: ServiceReconcilerStub(
        result: .failed(reason: "receipt missing")
      ),
      failureObservedAt: { "2026-07-29T01:00:03Z" }
    )

    XCTAssertThrowsError(try workflow.execute(command: command())) { error in
      XCTAssertEqual(
        error as? HostPlatformInstallationManagementError,
        .serviceReconciliationFailed("receipt missing")
      )
    }
    XCTAssertEqual(
      repository.operations["update-1"]?.state,
      .failed
    )
    XCTAssertEqual(repository.manifest?.installationRevision, 1)
  }
}

private final class HostInstallationRepositorySpy:
  HostPlatformInstallationRepository,
  @unchecked Sendable
{
  var manifest: HostPlatformInstallationManifest?
  var operations: [String: HostPlatformInstallationOperation] = [:]
  var events: [String] = []

  init(manifest: HostPlatformInstallationManifest?) {
    self.manifest = manifest
  }

  func initializeInstallation(
    _ manifest: HostPlatformInstallationManifest
  ) throws {
    self.manifest = manifest
  }

  func loadActiveInstallation() -> HostPlatformInstallationManifestReadResult {
    manifest.map(HostPlatformInstallationManifestReadResult.loaded)
      ?? .missing
  }

  func loadOperation(
    id: String
  ) -> HostPlatformInstallationOperationReadResult {
    operations[id].map(HostPlatformInstallationOperationReadResult.loaded)
      ?? .missing
  }

  func beginOperation(
    _ operation: HostPlatformInstallationOperation
  ) throws {
    operations[operation.id] = operation
    events.append(
      "begin:\(operation.state.rawValue):\(operation.operationRevision)"
    )
  }

  func saveOperation(
    _ operation: HostPlatformInstallationOperation,
    expectedOperationRevision: Int
  ) throws {
    operations[operation.id] = operation
    events.append(
      "save:\(operation.state.rawValue):\(operation.operationRevision):expected=\(expectedOperationRevision)"
    )
  }

  func settleSucceededOperation(
    _ operation: HostPlatformInstallationOperation,
    activeManifest: HostPlatformInstallationManifest,
    expectedOperationRevision: Int,
    expectedInstallationRevision: Int
  ) throws {
    operations[operation.id] = operation
    manifest = activeManifest
    events.append(
      "settle:\(operation.state.rawValue):\(operation.operationRevision):expectedOperation=\(expectedOperationRevision):expectedInstallation=\(expectedInstallationRevision)"
    )
  }

  func settleFailedOperation(
    _ operation: HostPlatformInstallationOperation,
    expectedOperationRevision: Int
  ) throws {
    operations[operation.id] = operation
    events.append(
      "settle-failed:\(operation.operationRevision):expected=\(expectedOperationRevision)"
    )
  }
}

private final class CandidateStagerStub:
  HostPlatformCandidateStaging,
  @unchecked Sendable
{
  let result: HostPlatformCandidateStagingResult
  var callCount = 0

  init(result: HostPlatformCandidateStagingResult) {
    self.result = result
  }

  func stageCandidate(
    command _: HostPlatformInstallationCommand
  ) -> HostPlatformCandidateStagingResult {
    callCount += 1
    return result
  }
}

private struct ServiceReconcilerStub:
  HostPlatformServiceReconciling
{
  let result: HostPlatformServiceReconciliationResult

  func reconcileServices(
    request _: HostPlatformServiceReconciliationRequest
  ) -> HostPlatformServiceReconciliationResult {
    result
  }
}

private func initialManifest() -> HostPlatformInstallationManifest {
  try! HostPlatformInstallationPolicy.makeInitialManifest(
    installationId: "installation-1",
    activeRelease: activeRelease(),
    operationId: "package-install-1",
    activatedAt: "2026-07-29T00:00:00Z"
  )
}

private func activeRelease() -> HostPlatformRelease {
  HostPlatformRelease(
    id: "host-0.2.1",
    version: "0.2.1",
    sha256: String(repeating: "a", count: 64),
    slotRelativePath: "releases/host-0.2.1/package.pkg"
  )
}

private func targetRelease() -> HostPlatformRelease {
  HostPlatformRelease(
    id: "host-0.2.2",
    version: "0.2.2",
    sha256: String(repeating: "b", count: 64),
    slotRelativePath: "releases/host-0.2.2/package.pkg"
  )
}

private func command() -> HostPlatformInstallationCommand {
  HostPlatformInstallationCommand(
    operationId: "update-1",
    kind: .apply,
    installationId: "installation-1",
    expectedInstallationRevision: 1,
    targetRelease: targetRelease(),
    sourceArtifactPath: "/incoming/host.pkg",
    sourceArtifactSizeBytes: 1024,
    sourceArtifactMediaType: HostPlatformReleaseArchiveContract.mediaType,
    stagingAttemptId: "attempt-1",
    requestedAt: "2026-07-29T01:00:00Z"
  )
}

private func candidate() -> HostPlatformStagedCandidate {
  HostPlatformStagedCandidate(
    release: targetRelease(),
    stagingReceiptId: "update-1.candidate",
    stagedAt: "2026-07-29T01:00:01Z"
  )
}

private func serviceReceipt() -> HostPlatformServiceReconciliationReceipt {
  HostPlatformServiceReconciliationReceipt(
    schemaVersion:
      HostPlatformInstallationPolicy.serviceReceiptSchemaVersion,
    reconciliationId: "update-1.services",
    operationId: "update-1",
    installationId: "installation-1",
    expectedInstallationRevision: 1,
    targetReleaseId: "host-0.2.2",
    targetReleaseSHA256: String(repeating: "b", count: 64),
    outcome: .succeeded,
    observedAt: "2026-07-29T01:00:02Z",
    failureReason: nil
  )
}

private func stagedOperation() throws -> HostPlatformInstallationOperation {
  let requested = try HostPlatformInstallationPolicy.makeRequestedOperation(
    command: command(),
    activeManifest: initialManifest()
  )
  return try HostPlatformInstallationPolicy.recordStagedCandidate(
    operation: requested,
    candidate: candidate(),
    updatedAt: "2026-07-29T01:00:01Z"
  )
}
