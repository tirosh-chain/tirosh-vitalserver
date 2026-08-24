import Application
import Contracts
import Domain
import OutboundAdapters
import Workflow
import XCTest

final class ManageHostPlatformInstallationWorkflowTests: XCTestCase {
  func testExecutePersistsEveryDurablePhaseAndSettlesAtomically() throws {
    let repository = HostInstallationRepositorySpy(
      manifest: initialManifest()
    )
    let reconciler = ReconcilerSpy(previous: previousManifest(), target: targetManifest())
    let workflow = ManageHostPlatformInstallationWorkflow(
      repository: repository,
      candidateStager: CandidateStagerStub(result: .staged(candidate())),
      reconciler: reconciler,
      observedAt: { "2026-07-29T01:00:03Z" }
    )

    let result = try workflow.execute(command: command())

    XCTAssertEqual(result.phase, .completed)
    XCTAssertEqual(
      repository.events,
      [
        "begin:requested:1",
        "save:prepared:2:expected=1",
        "save:previous-quiesced:3:expected=2",
        "save:interfaces-published:4:expected=3",
        "save:target-activated:5:expected=4",
        "save:target-services-loaded:6:expected=5",
        "settle:completed:7:expectedOperation=6:expectedInstallation=1",
      ]
    )
    XCTAssertEqual(reconciler.calls, [
      "quiesce:platform-agent",
      "publish:host-0.2.2",
      "activate:host-0.2.2",
      "load:platform-agent",
    ])
    XCTAssertEqual(
      repository.manifest?.activeRelease.id,
      "host-0.2.2"
    )
  }

  func testResumeFromEachDurablePhaseSkipsCompletedEffects() throws {
    for seeded in [
      try stagedOperation(),
      try quiescedOperation(),
      try publishedOperation(),
      try activatedOperation(),
    ] {
      let repository = HostInstallationRepositorySpy(
        manifest: initialManifest()
      )
      repository.operations[seeded.id] = seeded
      let reconciler = ReconcilerSpy(
        previous: previousManifest(),
        target: targetManifest()
      )
      let stager = CandidateStagerStub(result: .failed(reason: "must not run"))
      let workflow = ManageHostPlatformInstallationWorkflow(
        repository: repository,
        candidateStager: stager,
        reconciler: reconciler,
        observedAt: { "2026-07-29T01:00:03Z" }
      )

      let result = try workflow.execute(command: command())

      XCTAssertEqual(result.phase, .completed, "phase=\(seeded.phase)")
      XCTAssertEqual(stager.callCount, 0, "phase=\(seeded.phase)")
      XCTAssertFalse(
        reconciler.calls.contains("publish:host-0.2.2") && seeded.phase == .interfacesPublished,
        "publish must not repeat for phase=\(seeded.phase)"
      )
    }
  }

  func testResumeAfterActivationBeforeJournalSaveCompletesWithoutRepublish() throws {
    // Crash happened after the symlink was switched to target but before the
    // activateTarget journal entry persisted. The durable phase stays at
    // interfacesPublished while the link already resolves to target.
    let repository = HostInstallationRepositorySpy(manifest: initialManifest())
    let seeded = try publishedOperation()
    repository.operations[seeded.id] = seeded
    let reconciler = ReconcilerSpy(
      previous: previousManifest(),
      target: targetManifest()
    )
    reconciler.currentTarget = .resolved(targetRoot)
    let workflow = ManageHostPlatformInstallationWorkflow(
      repository: repository,
      candidateStager: CandidateStagerStub(result: .failed(reason: "must not run")),
      reconciler: reconciler,
      observedAt: { "2026-07-29T01:00:03Z" }
    )

    let result = try workflow.execute(command: command())

    XCTAssertEqual(result.phase, .completed)
    XCTAssertFalse(reconciler.calls.contains("publish:host-0.2.2"))
    XCTAssertFalse(reconciler.calls.contains("quiesce:[platform-agent]"))
  }

  func testTargetLoadFailureCompensatesAndFailsTerminally() throws {
    let repository = HostInstallationRepositorySpy(manifest: initialManifest())
    let reconciler = ReconcilerSpy(
      previous: previousManifest(),
      target: targetManifest()
    )
    reconciler.failLoadCallNumbers = [1]

    let workflow = ManageHostPlatformInstallationWorkflow(
      repository: repository,
      candidateStager: CandidateStagerStub(result: .staged(candidate())),
      reconciler: reconciler,
      observedAt: { "2026-07-29T01:00:03Z" }
    )

    XCTAssertThrowsError(try workflow.execute(command: command())) { error in
      guard case .reconciliationFailed(let reason) =
        error as? HostPlatformInstallationManagementError
      else {
        return XCTFail("unexpected error \(error)")
      }
      XCTAssertTrue(reason.contains("previous release restored"))
    }
    XCTAssertEqual(
      repository.operations["update-1"]?.phase,
      .failed
    )
    // Compensation restores previous interfaces, activation, and services.
    XCTAssertTrue(reconciler.calls.contains("publish:host-0.2.1"))
    XCTAssertTrue(reconciler.calls.contains("activate:host-0.2.1"))
    XCTAssertEqual(
      reconciler.calls.filter { $0.hasPrefix("load:") },
      ["load:platform-agent", "load:platform-agent"]
    )
    XCTAssertEqual(repository.manifest?.installationRevision, 1)
  }

  func testStagingFailureIsTerminalWithoutCompensation() throws {
    let repository = HostInstallationRepositorySpy(manifest: initialManifest())
    let reconciler = ReconcilerSpy(
      previous: previousManifest(),
      target: targetManifest()
    )
    let workflow = ManageHostPlatformInstallationWorkflow(
      repository: repository,
      candidateStager: CandidateStagerStub(result: .failed(reason: "bad archive")),
      reconciler: reconciler,
      observedAt: { "2026-07-29T01:00:03Z" }
    )

    XCTAssertThrowsError(try workflow.execute(command: command())) { error in
      XCTAssertEqual(
        error as? HostPlatformInstallationManagementError,
        .stagingFailed("bad archive")
      )
    }
    XCTAssertEqual(repository.operations["update-1"]?.phase, .failed)
    XCTAssertEqual(reconciler.calls, [])
  }

  func testFailedOperationCannotBeRetriedWithoutExplicitReset() throws {
    let repository = HostInstallationRepositorySpy(manifest: initialManifest())
    let failed = try HostPlatformInstallationPolicy.recordFailure(
      operation: HostPlatformInstallationPolicy.makeRequestedOperation(
        command: command(),
        activeManifest: initialManifest()
      ),
      reason: "staging failed",
      updatedAt: "2026-07-29T01:00:02Z"
    )
    repository.operations[failed.id] = failed
    let workflow = ManageHostPlatformInstallationWorkflow(
      repository: repository,
      candidateStager: CandidateStagerStub(result: .staged(candidate())),
      reconciler: ReconcilerSpy(previous: previousManifest(), target: targetManifest()),
      observedAt: { "2026-07-29T01:00:03Z" }
    )

    XCTAssertThrowsError(try workflow.execute(command: command())) { error in
      XCTAssertEqual(
        error as? HostPlatformInstallationManagementError,
        .operationAlreadyFailed("staging failed")
      )
    }
  }

  func testPreReconcileFailureAtPreparedTerminalizesWithoutCompensation() throws {
    let repository = HostInstallationRepositorySpy(manifest: initialManifest())
    let seeded = try stagedOperation()
    repository.operations[seeded.id] = seeded
    let reconciler = ReconcilerSpy(
      previous: previousManifest(),
      target: targetManifest()
    )
    reconciler.failTopology = true
    let workflow = ManageHostPlatformInstallationWorkflow(
      repository: repository,
      candidateStager: CandidateStagerStub(result: .failed(reason: "must not run")),
      reconciler: reconciler,
      observedAt: { "2026-07-29T01:00:03Z" }
    )

    XCTAssertThrowsError(try workflow.execute(command: command())) { error in
      guard case .topologyMismatch =
        error as? HostPlatformInstallationManagementError
      else {
        return XCTFail("unexpected error \(error)")
      }
    }
    XCTAssertEqual(repository.operations["update-1"]?.phase, .failed)
    // No irreversible effect ran and no compensation was attempted.
    XCTAssertEqual(reconciler.calls, [])
  }

  func testCompensationPersistenceFailureIsNotMisrecordedAsCompensationFailure() throws {
    let repository = HostInstallationRepositorySpy(manifest: initialManifest())
    repository.saveFailures = [.compensated]
    let reconciler = ReconcilerSpy(
      previous: previousManifest(),
      target: targetManifest()
    )
    reconciler.failLoadCallNumbers = [1]
    let workflow = ManageHostPlatformInstallationWorkflow(
      repository: repository,
      candidateStager: CandidateStagerStub(result: .staged(candidate())),
      reconciler: reconciler,
      observedAt: { "2026-07-29T01:00:03Z" }
    )

    XCTAssertThrowsError(try workflow.execute(command: command())) { error in
      XCTAssertEqual(
        error as? RepositorySpyFailure,
        .persistence("save compensated")
      )
    }
    // The durable state stays .compensating (compensation effect already
    // succeeded), and it is never mislabeled as a compensation failure.
    XCTAssertEqual(repository.operations["update-1"]?.phase, .compensating)
    let failureReason = repository.operations["update-1"]?.failureReason
    XCTAssertNotNil(failureReason)
    if let failureReason {
      XCTAssertFalse(failureReason.contains("compensation failed"))
    }
  }

  func testCompensationPersistenceFailureRetriesOnResume() throws {
    let repository = HostInstallationRepositorySpy(manifest: initialManifest())
    repository.saveFailures = [.compensated]
    let reconciler = ReconcilerSpy(
      previous: previousManifest(),
      target: targetManifest()
    )
    reconciler.failLoadCallNumbers = [1]
    let workflow = ManageHostPlatformInstallationWorkflow(
      repository: repository,
      candidateStager: CandidateStagerStub(result: .staged(candidate())),
      reconciler: reconciler,
      observedAt: { "2026-07-29T01:00:03Z" }
    )

    XCTAssertThrowsError(try workflow.execute(command: command())) { error in
      XCTAssertEqual(
        error as? RepositorySpyFailure,
        .persistence("save compensated")
      )
    }
    XCTAssertEqual(repository.operations["update-1"]?.phase, .compensating)

    // Persistence recovers; resume re-runs compensation idempotently and
    // terminalizes the operation.
    repository.saveFailures = []
    XCTAssertThrowsError(try workflow.execute(command: command())) { error in
      guard case .operationAlreadyFailed =
        error as? HostPlatformInstallationManagementError
      else {
        return XCTFail("unexpected error \(error)")
      }
    }
    XCTAssertEqual(repository.operations["update-1"]?.phase, .failed)
    XCTAssertTrue(reconciler.calls.contains("publish:host-0.2.1"))
  }

  func testCompensationEffectAndTerminalPersistenceFailureAreBothPreserved() throws {
    let repository = HostInstallationRepositorySpy(manifest: initialManifest())
    repository.failSettleFailed = true
    let reconciler = ReconcilerSpy(
      previous: previousManifest(),
      target: targetManifest()
    )
    reconciler.failLoadCallNumbers = [1]
    reconciler.failPublishIds = ["host-0.2.1"]
    let workflow = ManageHostPlatformInstallationWorkflow(
      repository: repository,
      candidateStager: CandidateStagerStub(result: .staged(candidate())),
      reconciler: reconciler,
      observedAt: { "2026-07-29T01:00:03Z" }
    )

    XCTAssertThrowsError(try workflow.execute(command: command())) { error in
      guard
        let composite = error as? HostPlatformCompensationPersistenceFailure
      else {
        return XCTFail("unexpected error \(error)")
      }
      XCTAssertEqual(
        composite.compensation
          as? MacOSHostPlatformReleaseServiceReconciliationError,
        .publicationFailed(path: "host-0.2.1", reason: "test publish failure")
      )
      XCTAssertEqual(
        composite.persistence as? RepositorySpyFailure,
        .persistence("settle failed")
      )
    }
    // Neither failure was hidden: the durable state stays .compensating so a
    // resume can retry compensation idempotently.
    XCTAssertEqual(repository.operations["update-1"]?.phase, .compensating)
    XCTAssertNotNil(repository.operations["update-1"]?.failureReason)
  }
}

private enum RepositorySpyFailure: Error, Equatable {
  case persistence(String)
}

private final class HostInstallationRepositorySpy:
  HostPlatformInstallationRepository,
  @unchecked Sendable
{
  var manifest: HostPlatformInstallationManifest?
  var operations: [String: HostPlatformInstallationOperation] = [:]
  var events: [String] = []
  var saveFailures: Set<HostPlatformInstallationPhase> = []
  var failSettleFailed = false

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
      "begin:\(operation.phase.rawValue):\(operation.operationRevision)"
    )
  }

  func saveOperation(
    _ operation: HostPlatformInstallationOperation,
    expectedOperationRevision: Int
  ) throws {
    if saveFailures.contains(operation.phase) {
      throw RepositorySpyFailure.persistence("save \(operation.phase.rawValue)")
    }
    operations[operation.id] = operation
    events.append(
      "save:\(operation.phase.rawValue):\(operation.operationRevision):expected=\(expectedOperationRevision)"
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
      "settle:\(operation.phase.rawValue):\(operation.operationRevision):expectedOperation=\(expectedOperationRevision):expectedInstallation=\(expectedInstallationRevision)"
    )
  }

  func settleFailedOperation(
    _ operation: HostPlatformInstallationOperation,
    expectedOperationRevision: Int
  ) throws {
    if failSettleFailed {
      throw RepositorySpyFailure.persistence("settle failed")
    }
    operations[operation.id] = operation
    events.append(
      "settle-failed:\(operation.operationRevision):expected=\(expectedOperationRevision)"
    )
  }
}

private final class ReconcilerSpy:
  HostPlatformReleaseReconciling,
  @unchecked Sendable
{
  let previous: HostPlatformReleaseArchiveManifest
  let target: HostPlatformReleaseArchiveManifest
  var currentTarget: HostPlatformCurrentReleaseTargetRead
  var failTopology = false
  var failLoadCallNumbers: Set<Int> = []
  var failPublishIds: Set<String> = []
  private(set) var calls: [String] = []
  private var loadCallCount = 0

  init(
    previous: HostPlatformReleaseArchiveManifest,
    target: HostPlatformReleaseArchiveManifest
  ) {
    self.previous = previous
    self.target = target
    self.currentTarget = .resolved(previous.releaseRootPath)
  }

  func loadReleaseManifest(
    _ release: HostPlatformRelease,
    installationId _: String
  ) -> HostPlatformReleaseManifestLoadResult {
    release.id == target.release.id ? .loaded(target) : .loaded(previous)
  }

  func verifyTopology(
    previous _: HostPlatformReleaseArchiveManifest,
    target _: HostPlatformReleaseArchiveManifest
  ) throws {
    if failTopology {
      throw MacOSHostPlatformReleaseServiceReconciliationError
        .manifestMismatch("test topology mismatch")
    }
  }

  func readCurrentReleaseTarget() -> HostPlatformCurrentReleaseTargetRead {
    currentTarget
  }

  func readServiceStates(
    _ services: [HostPlatformRequiredService]
  ) -> [HostPlatformLaunchdServiceObservation] {
    services.map {
      HostPlatformLaunchdServiceObservation(
        role: $0.role,
        serviceName: $0.name,
        action: .print,
        exitCode: 0,
        outcome: .loaded
      )
    }
  }

  func quiesceServices(
    _ services: [HostPlatformRequiredService]
  ) throws -> [HostPlatformLaunchdServiceObservation] {
    calls.append("quiesce:\(services.map(\.role).joined(separator: ","))")
    return services.map {
      HostPlatformLaunchdServiceObservation(
        role: $0.role,
        serviceName: $0.name,
        action: .bootout,
        exitCode: 0,
        outcome: .accepted
      )
    }
  }

  func publishInterfaces(
    _ manifest: HostPlatformReleaseArchiveManifest
  ) throws {
    calls.append("publish:\(manifest.release.id)")
    if failPublishIds.contains(manifest.release.id) {
      throw MacOSHostPlatformReleaseServiceReconciliationError
        .publicationFailed(
          path: manifest.release.id,
          reason: "test publish failure"
        )
    }
  }

  func activateTarget(
    _ manifest: HostPlatformReleaseArchiveManifest
  ) throws -> String {
    calls.append("activate:\(manifest.release.id)")
    currentTarget = .resolved(manifest.releaseRootPath)
    return manifest.releaseRootPath
  }

  func loadServices(
    _ services: [HostPlatformRequiredService]
  ) throws -> [HostPlatformLaunchdServiceObservation] {
    loadCallCount += 1
    calls.append("load:\(services.map(\.role).joined(separator: ","))")
    if failLoadCallNumbers.contains(loadCallCount) {
      throw MacOSHostPlatformReleaseServiceReconciliationError
        .serviceCommandFailed(
          action: "bootstrap",
          service: services.first?.name ?? "unknown",
          status: 5,
          reason: "bootstrap rejected"
        )
    }
    return services.map {
      HostPlatformLaunchdServiceObservation(
        role: $0.role,
        serviceName: $0.name,
        action: .print,
        exitCode: 0,
        outcome: .loaded
      )
    }
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

private let previousRoot =
  "/install/releases/host-0.2.1/release"
private let targetRoot =
  "/install/releases/host-0.2.2/release"

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

private func previousManifest() -> HostPlatformReleaseArchiveManifest {
  archiveManifest(id: "host-0.2.1", root: previousRoot)
}

private func targetManifest() -> HostPlatformReleaseArchiveManifest {
  archiveManifest(id: "host-0.2.2", root: targetRoot)
}

private func archiveManifest(
  id: String,
  root: String
) -> HostPlatformReleaseArchiveManifest {
  HostPlatformReleaseArchiveManifest(
    schemaVersion: HostPlatformReleaseArchiveContract.manifestSchemaVersion,
    installationId: "installation-1",
    release: HostPlatformReleaseIdentity(id: id, version: "0.2.2"),
    releaseCatalogPath: "/install",
    releaseRootPath: root,
    currentReleaseLinkPath: "/install/current",
    files: [],
    operatorInterface: HostPlatformOperatorInterface(
      bootstrapConfigurationPath: "/config/bootstrap.json",
      bootstrapConfigurationSha256: String(repeating: "c", count: 64),
      applicationBundlePath: "/Applications/VitalServer Helper.app",
      applicationBundleRelativePath: "app/VitalServer Helper.app",
      applicationBundleTreeSha256: String(repeating: "d", count: 64),
      applicationBundleEntrypointRelativePath:
        "Contents/MacOS/VitalServer Helper"
    ),
    replaceableServices: [
      HostPlatformRequiredService(
        role: "platform-agent",
        manager: "launchd",
        name: "ai.tirosh.vitalserver.helper.platform-agent",
        definitionPath: "/LaunchDaemons/platform-agent.plist",
        definitionSha256: String(repeating: "e", count: 64)
      ),
    ],
    stableComponents: [
      HostPlatformStableComponent(
        role: "host-installation-manager",
        executablePath: "/usr/local/bin/vitalserver-host-installation-manager",
        serviceName: nil
      ),
      HostPlatformStableComponent(
        role: "update-handoff-supervisor",
        executablePath: "/usr/local/bin/vitalserver-update-handoff-supervisor",
        serviceName: "ai.tirosh.vitalserver.helper.update-handoff-supervisor"
      ),
    ],
    mutableStores: []
  )
}

private func stagedOperation() throws -> HostPlatformInstallationOperation {
  try HostPlatformInstallationPolicy.recordStagedCandidate(
    operation: HostPlatformInstallationPolicy.makeRequestedOperation(
      command: command(),
      activeManifest: initialManifest()
    ),
    candidate: candidate(),
    updatedAt: "2026-07-29T01:00:01Z"
  )
}

private func quiescedOperation() throws -> HostPlatformInstallationOperation {
  try HostPlatformInstallationPolicy.recordQuiescePrevious(
    operation: stagedOperation(),
    observations: [],
    updatedAt: "2026-07-29T01:00:02Z"
  )
}

private func publishedOperation() throws -> HostPlatformInstallationOperation {
  try HostPlatformInstallationPolicy.recordPublishInterfaces(
    operation: quiescedOperation(),
    updatedAt: "2026-07-29T01:00:03Z"
  )
}

private func activatedOperation() throws -> HostPlatformInstallationOperation {
  try HostPlatformInstallationPolicy.recordActivateTarget(
    operation: publishedOperation(),
    resolvedTarget: targetRoot,
    updatedAt: "2026-07-29T01:00:04Z"
  )
}
