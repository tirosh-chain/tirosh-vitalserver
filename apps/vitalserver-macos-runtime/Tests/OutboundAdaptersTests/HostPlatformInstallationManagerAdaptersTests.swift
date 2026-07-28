import Application
import Contracts
import CryptoKit
import Domain
import Foundation
import OutboundAdapters
import XCTest

final class HostPlatformInstallationManagerAdaptersTests: XCTestCase {
  func testSQLiteRepositoryAtomicallySettlesOperationAndManifest() throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = makeRepository(
      databaseURL: root.appendingPathComponent("state.sqlite")
    )
    let manifest = try initialManifest()
    try repository.initializeInstallation(manifest)
    let requested = try requestedOperation(manifest: manifest)
    try repository.beginOperation(requested)
    let staged =
      try HostPlatformInstallationPolicy
      .recordStagedCandidate(
        operation: requested,
        candidate: candidate(),
        updatedAt: "2026-07-29T01:00:01Z"
      )
    try repository.saveOperation(
      staged,
      expectedOperationRevision: requested.operationRevision
    )
    let reconciled =
      try HostPlatformInstallationPolicy
      .recordServiceReconciliation(
        operation: staged,
        receipt: serviceReceipt()
      )
    try repository.saveOperation(
      reconciled,
      expectedOperationRevision: staged.operationRevision
    )
    let settlement =
      try HostPlatformInstallationPolicy
      .makeSucceededSettlement(operation: reconciled)

    try repository.settleSucceededOperation(
      settlement.operation,
      activeManifest: settlement.manifest,
      expectedOperationRevision: reconciled.operationRevision,
      expectedInstallationRevision: 1
    )

    XCTAssertEqual(
      repository.loadActiveInstallation(),
      .loaded(settlement.manifest)
    )
    XCTAssertEqual(
      repository.loadOperation(id: "update-1"),
      .loaded(settlement.operation)
    )
  }

  func testSQLiteRepositoryRejectsStaleInstallationSettlement() throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let repository = makeRepository(
      databaseURL: root.appendingPathComponent("state.sqlite")
    )
    let manifest = try initialManifest()
    try repository.initializeInstallation(manifest)
    let requested = try requestedOperation(manifest: manifest)
    try repository.beginOperation(requested)

    XCTAssertThrowsError(
      try repository.settleFailedOperation(
        try HostPlatformInstallationPolicy.recordFailure(
          operation: requested,
          reason: "failed",
          updatedAt: "2026-07-29T01:00:01Z"
        ),
        expectedOperationRevision: 99
      )
    ) { error in
      XCTAssertEqual(
        error as? SQLiteHostPlatformInstallationRepositoryError,
        .staleOperationRevision(expected: 99, actual: 1)
      )
    }
  }

  func testImmutableStagerVerifiesDigestAndRefusesExistingSlot() throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("candidate.pkg")
    let payload = Data("candidate".utf8)
    try payload.write(to: source)
    let digest = SHA256.hash(data: payload).map {
      String(format: "%02x", $0)
    }.joined()
    let command = makeCommand(
      sourcePath: source.path,
      targetSHA256: digest
    )
    let stager = ImmutableHostPlatformCandidateStager(
      installationRoot: root.appendingPathComponent("installed"),
      observedAt: { "2026-07-29T01:00:01Z" }
    )

    let firstResult = stager.stageCandidate(command: command)
    guard case .staged = firstResult else {
      return XCTFail("first staging must succeed result=\(firstResult)")
    }
    guard
      case .failed(let reason) =
        stager.stageCandidate(command: command)
    else {
      return XCTFail("existing immutable slot must fail")
    }
    XCTAssertTrue(reason.contains("destinationAlreadyExists"))
  }

  func testImmutableStagerDoesNotCreateStateForDigestMismatch() throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let source = root.appendingPathComponent("candidate.pkg")
    try Data("candidate".utf8).write(to: source)
    let stager = ImmutableHostPlatformCandidateStager(
      installationRoot: root.appendingPathComponent("installed"),
      observedAt: { "2026-07-29T01:00:01Z" }
    )

    let result = stager.stageCandidate(
      command: makeCommand(
        sourcePath: source.path,
        targetSHA256: String(repeating: "c", count: 64)
      )
    )

    guard case .failed(let reason) = result else {
      return XCTFail("digest mismatch must fail")
    }
    XCTAssertTrue(reason.contains("sourceDigestMismatch"))
    XCTAssertFalse(
      FileManager.default.fileExists(
        atPath: root.appendingPathComponent("installed").path
      )
    )
  }
}

extension HostPlatformInstallationManagerAdaptersTests {
  fileprivate func makeRepository(
    databaseURL: URL
  ) -> SQLiteHostPlatformInstallationRepository {
    SQLiteHostPlatformInstallationRepository(
      databaseURL: databaseURL,
      validateManifest: HostPlatformInstallationPolicy.validate,
      validateOperation: HostPlatformInstallationPolicy.validate,
      validateTransition:
        HostPlatformInstallationPolicy.validatePersistenceTransition
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

  fileprivate func requestedOperation(
    manifest: HostPlatformInstallationManifest
  ) throws -> HostPlatformInstallationOperation {
    try HostPlatformInstallationPolicy.makeRequestedOperation(
      command: makeCommand(
        sourcePath: "/incoming/host.pkg",
        targetSHA256: String(repeating: "b", count: 64)
      ),
      activeManifest: manifest
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

  fileprivate func targetRelease(sha256: String) -> HostPlatformRelease {
    HostPlatformRelease(
      id: "host-0.2.2",
      version: "0.2.2",
      sha256: sha256,
      slotRelativePath: "releases/host-0.2.2/package.pkg"
    )
  }

  fileprivate func makeCommand(
    sourcePath: String,
    targetSHA256: String
  ) -> HostPlatformInstallationCommand {
    HostPlatformInstallationCommand(
      operationId: "update-1",
      kind: .apply,
      installationId: "installation-1",
      expectedInstallationRevision: 1,
      targetRelease: targetRelease(sha256: targetSHA256),
      sourceArtifactPath: sourcePath,
      stagingAttemptId: "attempt-1",
      requestedAt: "2026-07-29T01:00:00Z"
    )
  }

  fileprivate func candidate() -> HostPlatformStagedCandidate {
    HostPlatformStagedCandidate(
      release: targetRelease(
        sha256: String(repeating: "b", count: 64)
      ),
      stagingReceiptId: "update-1.candidate",
      stagedAt: "2026-07-29T01:00:01Z"
    )
  }

  fileprivate func serviceReceipt() -> HostPlatformServiceReconciliationReceipt {
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

  fileprivate func temporaryDirectory() -> URL {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
      "host-platform-manager-tests-\(UUID().uuidString)",
      isDirectory: true
    )
    try! FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
    return directory
  }
}
