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

  func testHelperHostArchiveStagesVerifiedImmutableRelease() throws {
    let root = temporaryDirectory()
    defer { try? FileManager.default.removeItem(at: root) }
    let installationRoot = root.appendingPathComponent(
      "installed",
      isDirectory: true
    )
    let sourceRoot = root.appendingPathComponent("archive-source")
    let releaseRoot = sourceRoot.appendingPathComponent("release")
    let applicationRelativePath = "app/VitalServer Helper.app"
    let applicationRoot = releaseRoot.appendingPathComponent(
      applicationRelativePath
    )
    let entrypointRelativePath =
      "Contents/MacOS/VitalServer Helper"
    let entrypoint = applicationRoot.appendingPathComponent(
      entrypointRelativePath
    )
    let services = sourceRoot.appendingPathComponent("service-definitions")
    let operatorRoot = sourceRoot.appendingPathComponent("operator-interface")
    for directory in [
      entrypoint.deletingLastPathComponent(), services, operatorRoot,
    ] {
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
      )
    }
    let executableData = Data("helper-next".utf8)
    let serviceData = Data("vm-plist".utf8)
    let bootstrapData = Data("bootstrap".utf8)
    try executableData.write(to: entrypoint)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: entrypoint.path
    )
    try serviceData.write(
      to: services.appendingPathComponent("vm.plist")
    )
    try bootstrapData.write(
      to: operatorRoot.appendingPathComponent(
        "runtime-console-bootstrap.json"
      )
    )
    let destination = installationRoot.appendingPathComponent(
      "releases/host-0.2.2"
    )
    let manifest: [String: Any] = [
      "schemaVersion":
        HostPlatformReleaseArchiveContract.manifestSchemaVersion,
      "installationId": "installation-1",
      "release": ["id": "host-0.2.2", "version": "0.2.2"],
      "releaseCatalogPath": installationRoot.path,
      "releaseRootPath":
        destination.appendingPathComponent("release").path,
      "currentReleaseLinkPath":
        installationRoot.appendingPathComponent("current").path,
      "files": [[
        "relativePath":
          "\(applicationRelativePath)/\(entrypointRelativePath)",
        "sha256": sha256(executableData),
        "executable": true,
      ]],
      "operatorInterface": [
        "bootstrapConfigurationPath":
          root.appendingPathComponent("control/bootstrap.json").path,
        "bootstrapConfigurationSha256": sha256(bootstrapData),
        "applicationBundlePath":
          root.appendingPathComponent("Applications/VitalServer Helper.app").path,
        "applicationBundleRelativePath": applicationRelativePath,
        "applicationBundleTreeSha256": applicationTreeSHA256(
          relativePath: entrypointRelativePath,
          data: executableData
        ),
        "applicationBundleEntrypointRelativePath":
          entrypointRelativePath,
      ],
      "replaceableServices": [[
        "role": "vm",
        "manager": "launchd",
        "name": "ai.tirosh.vitalserver.helper.vm",
        "definitionPath":
          root.appendingPathComponent("LaunchDaemons/vm.plist").path,
        "definitionSha256": sha256(serviceData),
      ]],
      "stableComponents": [
        [
          "role": "host-installation-manager",
          "executablePath":
            root.appendingPathComponent(
              "stable/vitalserver-host-installation-manager"
            ).path,
        ],
        [
          "role": "update-handoff-supervisor",
          "executablePath":
            root.appendingPathComponent(
              "stable/vitalserver-update-handoff-supervisor"
            ).path,
          "serviceName":
            "ai.tirosh.vitalserver.helper.update-handoff-supervisor",
        ],
      ],
      "mutableStores": [[
        "id": "runtime-state",
        "path": root.appendingPathComponent("data").path,
        "kind": "directory",
        "owner": "vitalserver-helper",
        "retention": "preserve-by-default",
      ]],
    ]
    try JSONSerialization.data(
      withJSONObject: manifest,
      options: [.sortedKeys]
    ).write(
      to: releaseRoot.appendingPathComponent(
        "installation-manifest.json"
      )
    )
    let archive = root.appendingPathComponent("host-release.tar.gz")
    try run(
      "/usr/bin/tar",
      [
        "-czf", archive.path,
        "-C", sourceRoot.path,
        "release", "service-definitions", "operator-interface",
      ]
    )
    let archiveData = try Data(contentsOf: archive)
    let command = HostPlatformInstallationCommand(
      operationId: "update-archive-1",
      kind: .apply,
      installationId: "installation-1",
      expectedInstallationRevision: 1,
      targetRelease: HostPlatformRelease(
        id: "host-0.2.2",
        version: "0.2.2",
        sha256: sha256(archiveData),
        slotRelativePath: "releases/host-0.2.2"
      ),
      sourceArtifactPath: archive.path,
      sourceArtifactSizeBytes: UInt64(archiveData.count),
      sourceArtifactMediaType:
        HostPlatformReleaseArchiveContract.mediaType,
      stagingAttemptId: "archive-attempt-1",
      requestedAt: "2026-07-29T01:00:00Z"
    )

    let result = HostPlatformReleaseArchiveCandidateStager(
      installationRoot: installationRoot,
      observedAt: { "2026-07-29T01:00:01Z" }
    ).stageCandidate(command: command)

    guard case .staged(let candidate) = result else {
      return XCTFail("archive staging must succeed result=\(result)")
    }
    XCTAssertEqual(candidate.release.id, "host-0.2.2")
    XCTAssertTrue(
      FileManager.default.fileExists(
        atPath:
          destination
          .appendingPathComponent("release/installation-manifest.json")
          .path
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
      sourceArtifactSizeBytes: 7,
      sourceArtifactMediaType: HostPlatformReleaseArchiveContract.mediaType,
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

  fileprivate func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map {
      String(format: "%02x", $0)
    }.joined()
  }

  fileprivate func applicationTreeSHA256(
    relativePath: String,
    data: Data
  ) -> String {
    let fileDigest = sha256(data)
    var digest = SHA256()
    digest.update(data: Data("regular-file\0".utf8))
    digest.update(data: Data(relativePath.utf8))
    digest.update(data: Data([0]))
    digest.update(data: Data(fileDigest.utf8))
    digest.update(data: Data([0]))
    return digest.finalize().map {
      String(format: "%02x", $0)
    }.joined()
  }

  fileprivate func run(
    _ executable: String,
    _ arguments: [String]
  ) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.environment =
      ProcessInfo.processInfo.environment.merging(
        ["COPYFILE_DISABLE": "1"]
      ) { _, explicit in explicit }
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
  }
}
