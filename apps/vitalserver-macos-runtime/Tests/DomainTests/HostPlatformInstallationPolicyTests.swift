import Contracts
import Domain
import XCTest

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

  func testSuccessRequiresCorrelatedServiceOwnerReceipt() throws {
    let requested = try requestedOperation()
    let staged =
      try HostPlatformInstallationPolicy
      .recordStagedCandidate(
        operation: requested,
        candidate: candidate(),
        updatedAt: "2026-07-29T01:00:01Z"
      )
    let receipt = serviceReceipt(operationId: "another-operation")

    XCTAssertThrowsError(
      try HostPlatformInstallationPolicy.recordServiceReconciliation(
        operation: staged,
        receipt: receipt
      )
    ) { error in
      XCTAssertEqual(
        error as? HostPlatformInstallationPolicyError,
        .invalidServiceReceipt
      )
    }
  }

  func testSucceededSettlementAdvancesManifestAndRetainsRollback() throws {
    let requested = try requestedOperation()
    let staged =
      try HostPlatformInstallationPolicy
      .recordStagedCandidate(
        operation: requested,
        candidate: candidate(),
        updatedAt: "2026-07-29T01:00:01Z"
      )
    let reconciled =
      try HostPlatformInstallationPolicy
      .recordServiceReconciliation(
        operation: staged,
        receipt: serviceReceipt()
      )

    let settlement =
      try HostPlatformInstallationPolicy
      .makeSucceededSettlement(operation: reconciled)

    XCTAssertEqual(settlement.operation.state, .succeeded)
    XCTAssertEqual(settlement.manifest.installationRevision, 2)
    XCTAssertEqual(settlement.manifest.activeRelease, targetRelease())
    XCTAssertEqual(settlement.manifest.rollbackRelease, activeRelease())
    XCTAssertEqual(settlement.manifest.activationOperationId, "update-1")
  }

  func testIllegalTransitionDoesNotAdvanceOperation() throws {
    let requested = try requestedOperation()

    XCTAssertThrowsError(
      try HostPlatformInstallationPolicy.makeSucceededSettlement(
        operation: requested
      )
    ) { error in
      XCTAssertEqual(
        error as? HostPlatformInstallationPolicyError,
        .invalidTransition(from: .requested, event: "settle-succeeded")
      )
    }
  }
}

extension HostPlatformInstallationPolicyTests {
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

  fileprivate func serviceReceipt(
    operationId: String = "update-1"
  ) -> HostPlatformServiceReconciliationReceipt {
    HostPlatformServiceReconciliationReceipt(
      schemaVersion:
        HostPlatformInstallationPolicy.serviceReceiptSchemaVersion,
      reconciliationId: "\(operationId).services",
      operationId: operationId,
      installationId: "installation-1",
      expectedInstallationRevision: 1,
      targetReleaseId: "host-0.2.2",
      targetReleaseSHA256: String(repeating: "b", count: 64),
      outcome: .succeeded,
      observedAt: "2026-07-29T01:00:02Z",
      failureReason: nil
    )
  }
}
