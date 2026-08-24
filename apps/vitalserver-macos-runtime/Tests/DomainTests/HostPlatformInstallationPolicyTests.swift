import Contracts
import Domain
import XCTest

private let previousRoot =
  "/install/releases/host-0.2.1/release"
private let targetRoot =
  "/install/releases/host-0.2.2/release"

final class HostPlatformInstallationPolicyTests: XCTestCase {
  func testApplyRequiresExactInstallationFence() throws {
    let manifest = try initialManifest()
    let command = makeCommand(expectedRevision: 2)

    XCTAssertThrowsError(
      try HostPlatformInstallationPolicy.makeRequestedOperation(
        command: command,
        activeManifest: manifest
      )
    ) { error in
      XCTAssertEqual(
        error as? HostPlatformInstallationPolicyError,
        .installationRevisionMismatch(expected: 2, actual: 1)
      )
    }
  }

  func testRollbackRequiresManifestDeclaredRollbackRelease() throws {
    let manifest = try initialManifest()
    let command = makeCommand(kind: .rollback)

    XCTAssertThrowsError(
      try HostPlatformInstallationPolicy.makeRequestedOperation(
        command: command,
        activeManifest: manifest
      )
    ) { error in
      XCTAssertEqual(
        error as? HostPlatformInstallationPolicyError,
        .rollbackReleaseUnavailable
      )
    }
  }

  func testForwardPathAdvancesThroughEveryDurablePhase() throws {
    let operation = try advancedOperation()

    XCTAssertEqual(operation.phase, .targetServicesLoaded)
    XCTAssertEqual(
      operation.journal.map(\.phase),
      [
        .prepared,
        .previousQuiesced,
        .interfacesPublished,
        .targetActivated,
        .targetServicesLoaded,
      ]
    )
    let settlement = try HostPlatformInstallationPolicy
      .makeCompletedSettlement(
        operation: operation,
        settledAt: "2026-07-29T01:00:06Z"
      )
    XCTAssertEqual(settlement.operation.phase, .completed)
    XCTAssertEqual(settlement.manifest.installationRevision, 2)
    XCTAssertEqual(settlement.manifest.activeRelease, targetRelease())
    XCTAssertEqual(settlement.manifest.rollbackRelease, activeRelease())
    XCTAssertEqual(settlement.manifest.activationOperationId, "update-1")
  }

  func testNextStepResumesFromEachDurablePhase() throws {
    let prepared = try stagedOperation()
    XCTAssertEqual(
      try nextStep(prepared, current: .resolved(previousRoot)),
      .quiescePrevious
    )
    let quiesced = try HostPlatformInstallationPolicy
      .recordQuiescePrevious(
        operation: prepared,
        observations: [serviceObservation(role: "platform-agent")],
        updatedAt: "2026-07-29T01:00:02Z"
      )
    XCTAssertEqual(try nextStep(quiesced, current: .resolved(previousRoot)), .publishInterfaces)
    let published = try HostPlatformInstallationPolicy
      .recordPublishInterfaces(operation: quiesced, updatedAt: "2026-07-29T01:00:03Z")
    XCTAssertEqual(try nextStep(published, current: .resolved(previousRoot)), .activateTarget)
    let activated = try HostPlatformInstallationPolicy
      .recordActivateTarget(
        operation: published,
        resolvedTarget: targetRoot,
        updatedAt: "2026-07-29T01:00:04Z"
      )
    XCTAssertEqual(try nextStep(activated, current: .resolved(targetRoot)), .loadTargetServices)
    let loaded = try HostPlatformInstallationPolicy
      .recordLoadTargetServices(
        operation: activated,
        observations: [serviceObservation(role: "platform-agent")],
        updatedAt: "2026-07-29T01:00:05Z"
      )
    XCTAssertEqual(try nextStep(loaded, current: .resolved(targetRoot)), .settle)
  }

  func testNextStepDetectsDeepResumeAfterActivationCrash() throws {
    // Crash happened after the symlink was switched to target but before the
    // activateTarget journal entry was persisted: durable phase stays at
    // interfacesPublished while the symlink already resolves to target.
    let published = try publishedOperation()
    XCTAssertEqual(
      try nextStep(published, current: .resolved(targetRoot)),
      .activateTarget
    )

    // Even at prepared, if the link already resolves to target the workflow
    // acknowledges activation instead of re-quiescing.
    let prepared = try stagedOperation()
    XCTAssertEqual(
      try nextStep(prepared, current: .resolved(targetRoot)),
      .activateTarget
    )
  }

  func testNextStepRejectsUnprovenBaseline() throws {
    let prepared = try stagedOperation()
    XCTAssertThrowsError(
      try nextStep(prepared, current: .resolved("/unexpected/release"))
    ) { error in
      XCTAssertEqual(
        error as? HostPlatformInstallationPolicyError,
        .activeReleaseNotProven(
          "current target is neither previous nor target actual=/unexpected/release"
        )
      )
    }
    XCTAssertThrowsError(
      try nextStep(prepared, current: .notSymlink)
    ) { error in
      XCTAssertEqual(
        error as? HostPlatformInstallationPolicyError,
        .activeReleaseNotProven("current release link is not a symlink")
      )
    }
  }

  func testFailureCompensationAndTerminalFailureAreDurable() throws {
    let loaded = try advancedOperation()

    let compensating = try HostPlatformInstallationPolicy.recordCompensating(
      operation: loaded,
      reason: "target bootstrap failed",
      updatedAt: "2026-07-29T01:00:06Z"
    )
    XCTAssertEqual(compensating.phase, .compensating)
    XCTAssertEqual(compensating.failureReason, "target bootstrap failed")

    let compensated = try HostPlatformInstallationPolicy.recordCompensated(
      operation: compensating,
      updatedAt: "2026-07-29T01:00:07Z"
    )
    XCTAssertEqual(compensated.phase, .compensated)

    let failed = try HostPlatformInstallationPolicy.recordFailure(
      operation: compensated,
      reason: "target bootstrap failed",
      updatedAt: "2026-07-29T01:00:08Z"
    )
    XCTAssertEqual(failed.phase, .failed)
    XCTAssertEqual(
      failed.journal.map(\.phase),
      [
        .prepared,
        .previousQuiesced,
        .interfacesPublished,
        .targetActivated,
        .targetServicesLoaded,
        .compensating,
        .compensated,
        .failed,
      ]
    )
  }

  func testCandidateReceiptIdUsesBoundedIdentifierSyntax() throws {
    let operation = try requestedOperation()
    let canonical = "host-platform-candidate.\(String(repeating: "b", count: 64))"
    XCTAssertEqual(canonical.count, 88)
    XCTAssertTrue(UpdateBootstrapIdentifierSyntax.isIdentifier(canonical))

    let staged = try HostPlatformInstallationPolicy.recordStagedCandidate(
      operation: operation,
      candidate: HostPlatformStagedCandidate(
        release: targetRelease(),
        stagingReceiptId: canonical,
        stagedAt: "2026-07-29T01:00:01Z"
      ),
      updatedAt: "2026-07-29T01:00:01Z"
    )
    XCTAssertEqual(staged.candidate?.stagingReceiptId, canonical)
    XCTAssertEqual(staged.phase, .prepared)
  }

  func testCandidateReceiptIdRejectsOverlongConcatenationAndInvalidSyntax() throws {
    let operation = try requestedOperation()
    let overlong =
      String(repeating: "a", count: 64) + ".archive."
      + String(repeating: "b", count: 64)
    XCTAssertEqual(overlong.count, 137)
    XCTAssertFalse(UpdateBootstrapIdentifierSyntax.isIdentifier(overlong))
    XCTAssertThrowsError(
      try HostPlatformInstallationPolicy.recordStagedCandidate(
        operation: operation,
        candidate: HostPlatformStagedCandidate(
          release: targetRelease(),
          stagingReceiptId: overlong,
          stagedAt: "2026-07-29T01:00:01Z"
        ),
        updatedAt: "2026-07-29T01:00:01Z"
      )
    ) { error in
      XCTAssertEqual(
        error as? HostPlatformInstallationPolicyError,
        .invalidField("stagingReceiptId")
      )
    }

    XCTAssertThrowsError(
      try HostPlatformInstallationPolicy.recordStagedCandidate(
        operation: operation,
        candidate: HostPlatformStagedCandidate(
          release: targetRelease(),
          stagingReceiptId: "host-platform-candidate:colon",
          stagedAt: "2026-07-29T01:00:01Z"
        ),
        updatedAt: "2026-07-29T01:00:01Z"
      )
    ) { error in
      XCTAssertEqual(
        error as? HostPlatformInstallationPolicyError,
        .invalidField("stagingReceiptId")
      )
    }

    XCTAssertThrowsError(
      try HostPlatformInstallationPolicy.recordStagedCandidate(
        operation: operation,
        candidate: HostPlatformStagedCandidate(
          release: targetRelease(),
          stagingReceiptId: "host-platform-후보",
          stagedAt: "2026-07-29T01:00:01Z"
        ),
        updatedAt: "2026-07-29T01:00:01Z"
      )
    ) { error in
      XCTAssertEqual(
        error as? HostPlatformInstallationPolicyError,
        .invalidField("stagingReceiptId")
      )
    }

    XCTAssertThrowsError(
      try HostPlatformInstallationPolicy.recordStagedCandidate(
        operation: operation,
        candidate: HostPlatformStagedCandidate(
          release: targetRelease(),
          stagingReceiptId: "",
          stagedAt: "2026-07-29T01:00:01Z"
        ),
        updatedAt: "2026-07-29T01:00:01Z"
      )
    ) { error in
      XCTAssertEqual(
        error as? HostPlatformInstallationPolicyError,
        .invalidField("stagingReceiptId")
      )
    }
  }

  func testStagingFailureIsTerminalWithoutCompensation() throws {
    let requested = try requestedOperation()
    let failed = try HostPlatformInstallationPolicy.recordFailure(
      operation: requested,
      reason: "staging failed",
      updatedAt: "2026-07-29T01:00:01Z"
    )
    XCTAssertEqual(failed.phase, .failed)
    XCTAssertEqual(failed.journal.map(\.effect), [.fail])
  }

  func testJournalEffectPhaseMismatchIsRejected() throws {
    let prepared = try stagedOperation()
    var operation = try HostPlatformInstallationPolicy.recordQuiescePrevious(
      operation: prepared,
      observations: [],
      updatedAt: "2026-07-29T01:00:02Z"
    )
    let wrong = HostPlatformReconciliationJournalEntry(
      effect: .stageCandidate,
      phase: .previousQuiesced,
      currentReleaseTarget: nil,
      services: [],
      observedAt: "2026-07-29T01:00:02Z"
    )
    operation = HostPlatformInstallationOperation(
      schemaVersion: operation.schemaVersion,
      id: operation.id,
      operationRevision: operation.operationRevision,
      kind: operation.kind,
      phase: operation.phase,
      installationId: operation.installationId,
      expectedInstallationRevision: operation.expectedInstallationRevision,
      targetRelease: operation.targetRelease,
      previousRelease: operation.previousRelease,
      candidate: operation.candidate,
      journal: [wrong],
      failureReason: nil,
      requestedAt: operation.requestedAt,
      updatedAt: operation.updatedAt
    )
    XCTAssertThrowsError(
      try HostPlatformInstallationPolicy.validate(operation)
    ) { error in
      XCTAssertEqual(
        error as? HostPlatformInstallationPolicyError,
        .invalidJournal(
          "effect stage-candidate does not match phase previous-quiesced"
        )
      )
    }
  }

  func testPersistenceTransitionRequiresMonotonicRevision() throws {
    let prepared = try stagedOperation()
    let quiesced = try HostPlatformInstallationPolicy.recordQuiescePrevious(
      operation: prepared,
      observations: [],
      updatedAt: "2026-07-29T01:00:02Z"
    )
    XCTAssertNoThrow(
      try HostPlatformInstallationPolicy.validatePersistenceTransition(
        previous: prepared,
        next: quiesced
      )
    )
    XCTAssertThrowsError(
      try HostPlatformInstallationPolicy.validatePersistenceTransition(
        previous: prepared,
        next: prepared
      )
    )
  }

  func testPreparedOperationCanTerminalizeWithoutCompensation() throws {
    let prepared = try stagedOperation()
    let failed = try HostPlatformInstallationPolicy.recordFailure(
      operation: prepared,
      reason: "pre-reconcile proof failed",
      updatedAt: "2026-07-29T01:00:02Z"
    )
    XCTAssertEqual(failed.phase, .failed)
    XCTAssertEqual(failed.journal.map(\.phase), [.prepared, .failed])
    XCTAssertNoThrow(
      try HostPlatformInstallationPolicy.validatePersistenceTransition(
        previous: prepared,
        next: failed
      )
    )
  }

  func testCompletedSettlementRecordsExplicitSettleTime() throws {
    let operation = try advancedOperation()
    let settledAt = "2026-07-29T01:00:06Z"

    let settlement = try HostPlatformInstallationPolicy.makeCompletedSettlement(
      operation: operation,
      settledAt: settledAt
    )

    XCTAssertEqual(settlement.operation.phase, .completed)
    XCTAssertEqual(settlement.operation.updatedAt, settledAt)
    XCTAssertEqual(settlement.operation.journal.last?.observedAt, settledAt)
    XCTAssertEqual(settlement.manifest.activatedAt, settledAt)
    XCTAssertNotEqual(settlement.operation.updatedAt, operation.updatedAt)
  }
}

extension HostPlatformInstallationPolicyTests {
  fileprivate func nextStep(
    _ operation: HostPlatformInstallationOperation,
    current: HostPlatformCurrentReleaseTargetRead
  ) throws -> HostPlatformReconciliationStep {
    try HostPlatformInstallationPolicy.nextStep(
      operation: operation,
      currentReleaseTarget: current,
      previousReleaseRoot: previousRoot,
      targetReleaseRoot: targetRoot
    )
  }

  fileprivate func initialManifest() throws -> HostPlatformInstallationManifest {
    try HostPlatformInstallationPolicy.makeInitialManifest(
      installationId: "installation-1",
      activeRelease: activeRelease(),
      operationId: "package-install-1",
      activatedAt: "2026-07-29T00:00:00Z"
    )
  }

  fileprivate func requestedOperation() throws -> HostPlatformInstallationOperation {
    try HostPlatformInstallationPolicy.makeRequestedOperation(
      command: makeCommand(),
      activeManifest: initialManifest()
    )
  }

  fileprivate func stagedOperation() throws -> HostPlatformInstallationOperation {
    try HostPlatformInstallationPolicy.recordStagedCandidate(
      operation: requestedOperation(),
      candidate: candidate(),
      updatedAt: "2026-07-29T01:00:01Z"
    )
  }

  fileprivate func publishedOperation() throws -> HostPlatformInstallationOperation {
    let quiesced = try HostPlatformInstallationPolicy.recordQuiescePrevious(
      operation: stagedOperation(),
      observations: [],
      updatedAt: "2026-07-29T01:00:02Z"
    )
    return try HostPlatformInstallationPolicy.recordPublishInterfaces(
      operation: quiesced,
      updatedAt: "2026-07-29T01:00:03Z"
    )
  }

  fileprivate func advancedOperation() throws -> HostPlatformInstallationOperation {
    let published = try publishedOperation()
    let activated = try HostPlatformInstallationPolicy.recordActivateTarget(
      operation: published,
      resolvedTarget: targetRoot,
      updatedAt: "2026-07-29T01:00:04Z"
    )
    return try HostPlatformInstallationPolicy.recordLoadTargetServices(
      operation: activated,
      observations: [],
      updatedAt: "2026-07-29T01:00:05Z"
    )
  }

  fileprivate func makeCommand(
    kind: HostPlatformInstallationOperationKind = .apply,
    expectedRevision: Int = 1
  ) -> HostPlatformInstallationCommand {
    HostPlatformInstallationCommand(
      operationId: "update-1",
      kind: kind,
      installationId: "installation-1",
      expectedInstallationRevision: expectedRevision,
      targetRelease: targetRelease(),
      sourceArtifactPath: "/incoming/host-platform.pkg",
      sourceArtifactSizeBytes: 1024,
      sourceArtifactMediaType: HostPlatformReleaseArchiveContract.mediaType,
      stagingAttemptId: "attempt-1",
      requestedAt: "2026-07-29T01:00:00Z"
    )
  }

  fileprivate func activeRelease() -> HostPlatformRelease {
    HostPlatformRelease(
      id: "host-0.2.1",
      version: "0.2.1",
      sha256: String(repeating: "a", count: 64),
      slotRelativePath: "releases/host-0.2.1/package.pkg"
    )
  }

  fileprivate func targetRelease() -> HostPlatformRelease {
    HostPlatformRelease(
      id: "host-0.2.2",
      version: "0.2.2",
      sha256: String(repeating: "b", count: 64),
      slotRelativePath: "releases/host-0.2.2/package.pkg"
    )
  }

  fileprivate func candidate() -> HostPlatformStagedCandidate {
    HostPlatformStagedCandidate(
      release: targetRelease(),
      stagingReceiptId: "update-1.candidate",
      stagedAt: "2026-07-29T01:00:01Z"
    )
  }

  fileprivate func serviceObservation(
    role: String
  ) -> HostPlatformLaunchdServiceObservation {
    HostPlatformLaunchdServiceObservation(
      role: role,
      serviceName: "ai.tirosh.vitalserver.helper.\(role)",
      action: .print,
      exitCode: 0,
      outcome: .loaded
    )
  }
}
