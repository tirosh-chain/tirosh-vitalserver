import Application
import Contracts
import CryptoKit
import Foundation
import OutboundAdapters
import XCTest

final class HostPlatformReleaseArchiveCandidateStagerTests: XCTestCase {
  func testRejectsUndeclaredFileInCandidateArchive() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("stager-closure-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    let installationRoot = root.appendingPathComponent(
      "installed",
      isDirectory: true
    )
    let command = try buildArchive(
      root: root,
      extraFiles: ["release/undeclared.txt": Data("extra".utf8)]
    )

    let result = HostPlatformReleaseArchiveCandidateStager(
      installationRoot: installationRoot,
      observedAt: { "2026-07-29T01:00:01Z" }
    ).stageCandidate(command: command)

    guard case .failed(let reason) = result else {
      return XCTFail("undeclared file must be rejected result=\(result)")
    }
    XCTAssertTrue(reason.contains("unexpectedArchiveEntry"))
  }

  func testRejectsMissingDeclaredFileInCandidateArchive() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("stager-missing-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    let installationRoot = root.appendingPathComponent(
      "installed",
      isDirectory: true
    )
    let command = try buildArchive(
      root: root,
      omitDeclaredFile: true
    )

    let result = HostPlatformReleaseArchiveCandidateStager(
      installationRoot: installationRoot,
      observedAt: { "2026-07-29T01:00:01Z" }
    ).stageCandidate(command: command)

    guard case .failed(let reason) = result else {
      return XCTFail("missing declared file must be rejected result=\(result)")
    }
    XCTAssertTrue(reason.contains("missingArchiveEntry"))
  }

  func testResumeReturnsStagedWhenExistingSlotMatchesCommandProof() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("stager-resume-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    let installationRoot = root.appendingPathComponent(
      "installed",
      isDirectory: true
    )
    let command = try buildArchive(root: root)
    let stager = HostPlatformReleaseArchiveCandidateStager(
      installationRoot: installationRoot,
      observedAt: { "2026-07-29T01:00:01Z" }
    )

    guard case .staged(let first) = stager.stageCandidate(command: command) else {
      return XCTFail("first staging must succeed")
    }
    XCTAssertEqual(
      first.stagingReceiptId,
      "host-platform-candidate.\(command.targetRelease.sha256)"
    )
    XCTAssertEqual(first.stagingReceiptId.count, 88)
    XCTAssertLessThanOrEqual(first.stagingReceiptId.count, 128)
    let second = stager.stageCandidate(command: command)

    guard case .staged(let resumed) = second else {
      return XCTFail("matching existing slot must resume as staged result=\(second)")
    }
    XCTAssertEqual(resumed, first)
    XCTAssertEqual(resumed.release, command.targetRelease)
  }

  func testRollbackReusesExistingMatchingReleaseSlot() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("stager-rollback-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    let installationRoot = root.appendingPathComponent(
      "installed",
      isDirectory: true
    )
    let apply = try buildArchive(root: root)
    let stager = HostPlatformReleaseArchiveCandidateStager(
      installationRoot: installationRoot,
      observedAt: { "2026-07-29T01:00:01Z" }
    )
    guard case .staged = stager.stageCandidate(command: apply) else {
      return XCTFail("apply staging must succeed")
    }
    let rollback = makeCommand(
      operationId: "update-rollback-1",
      kind: .rollback,
      id: apply.targetRelease.id,
      version: apply.targetRelease.version,
      sha256: apply.targetRelease.sha256,
      slotRelativePath: apply.targetRelease.slotRelativePath,
      sourceArtifactPath: apply.sourceArtifactPath,
      sourceArtifactSizeBytes: apply.sourceArtifactSizeBytes,
      stagingAttemptId: "rollback-attempt-1"
    )

    let result = stager.stageCandidate(command: rollback)

    guard case .staged(let candidate) = result else {
      return XCTFail("rollback must reuse the existing matching slot result=\(result)")
    }
    XCTAssertEqual(candidate.release, rollback.targetRelease)
  }

  func testResumeRejectsExistingSlotWithMismatchedReleaseIdentity() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("stager-identity-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    let installationRoot = root.appendingPathComponent(
      "installed",
      isDirectory: true
    )
    let command = try buildArchive(root: root)
    let stager = HostPlatformReleaseArchiveCandidateStager(
      installationRoot: installationRoot,
      observedAt: { "2026-07-29T01:00:01Z" }
    )
    guard case .staged = stager.stageCandidate(command: command) else {
      return XCTFail("first staging must succeed")
    }
    // A genuine different release whose source archive declares a different
    // identity but targets the same slot path. The source archive matches the
    // command, so only the existing slot's identity mismatches.
    let foreign = try buildArchive(
      root: root,
      releaseId: "host-0.2.3",
      releaseVersion: "0.2.3",
      slotRelativePath: "releases/host-0.2.2"
    )
    let mismatched = makeCommand(
      operationId: "update-archive-2",
      kind: .apply,
      id: foreign.targetRelease.id,
      version: foreign.targetRelease.version,
      sha256: foreign.targetRelease.sha256,
      slotRelativePath: foreign.targetRelease.slotRelativePath,
      sourceArtifactPath: foreign.sourceArtifactPath,
      sourceArtifactSizeBytes: foreign.sourceArtifactSizeBytes,
      stagingAttemptId: "archive-attempt-2"
    )

    let result = stager.stageCandidate(command: mismatched)

    guard case .failed(let reason) = result else {
      return XCTFail("mismatched slot must be rejected result=\(result)")
    }
    XCTAssertTrue(reason.contains("stagedSlotMismatch"))
  }

  func testResumeRejectsSameIdentitySlotWithDifferentSourcePayload() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("stager-payload-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    let installationRoot = root.appendingPathComponent(
      "installed",
      isDirectory: true
    )
    let first = try buildArchive(root: root, executableContent: "helper-next")
    let stager = HostPlatformReleaseArchiveCandidateStager(
      installationRoot: installationRoot,
      observedAt: { "2026-07-29T01:00:01Z" }
    )
    guard case .staged = stager.stageCandidate(command: first) else {
      return XCTFail("first staging must succeed")
    }
    // A different, self-consistent archive with the SAME id/version but a
    // different payload, targeting the same slot.
    let second = try buildArchive(
      root: root,
      executableContent: "helper-different"
    )
    let mismatched = makeCommand(
      operationId: "update-archive-2",
      kind: .apply,
      id: second.targetRelease.id,
      version: second.targetRelease.version,
      sha256: second.targetRelease.sha256,
      slotRelativePath: first.targetRelease.slotRelativePath,
      sourceArtifactPath: second.sourceArtifactPath,
      sourceArtifactSizeBytes: second.sourceArtifactSizeBytes,
      stagingAttemptId: "archive-attempt-2"
    )

    let result = stager.stageCandidate(command: mismatched)

    guard case .failed(let reason) = result else {
      return XCTFail("same-identity different-payload slot must be rejected result=\(result)")
    }
    XCTAssertTrue(reason.contains("stagedSlotMismatch"))
  }

  func testResumeCleansUpTemporaryExtractionDirectory() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("stager-resume-cleanup-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    let installationRoot = root.appendingPathComponent(
      "installed",
      isDirectory: true
    )
    let command = try buildArchive(root: root)
    let stager = HostPlatformReleaseArchiveCandidateStager(
      installationRoot: installationRoot,
      observedAt: { "2026-07-29T01:00:01Z" }
    )
    guard case .staged = stager.stageCandidate(command: command) else {
      return XCTFail("first staging must succeed")
    }
    let temporary = installationRoot.appendingPathComponent(
      ".candidate-\(command.stagingAttemptId)",
      isDirectory: true
    )

    let result = stager.stageCandidate(command: command)

    guard case .staged = result else {
      return XCTFail("resume must succeed result=\(result)")
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path))
  }

  func testResumeCleansUpTemporaryAfterMismatch() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("stager-resume-mismatch-cleanup-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    let installationRoot = root.appendingPathComponent(
      "installed",
      isDirectory: true
    )
    let command = try buildArchive(root: root)
    let stager = HostPlatformReleaseArchiveCandidateStager(
      installationRoot: installationRoot,
      observedAt: { "2026-07-29T01:00:01Z" }
    )
    guard case .staged = stager.stageCandidate(command: command) else {
      return XCTFail("first staging must succeed")
    }
    let second = try buildArchive(root: root, executableContent: "helper-different")
    let mismatched = makeCommand(
      operationId: "update-archive-2",
      kind: .apply,
      id: second.targetRelease.id,
      version: second.targetRelease.version,
      sha256: second.targetRelease.sha256,
      slotRelativePath: command.targetRelease.slotRelativePath,
      sourceArtifactPath: second.sourceArtifactPath,
      sourceArtifactSizeBytes: second.sourceArtifactSizeBytes,
      stagingAttemptId: "archive-attempt-2"
    )
    let temporary = installationRoot.appendingPathComponent(
      ".candidate-archive-attempt-2",
      isDirectory: true
    )

    let result = stager.stageCandidate(command: mismatched)

    guard case .failed = result else {
      return XCTFail("mismatched payload must be rejected result=\(result)")
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: temporary.path))
  }

  func testResumeRejectsExistingSlotWithTamperedFile() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("stager-tamper-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    let installationRoot = root.appendingPathComponent(
      "installed",
      isDirectory: true
    )
    let command = try buildArchive(root: root)
    let stager = HostPlatformReleaseArchiveCandidateStager(
      installationRoot: installationRoot,
      observedAt: { "2026-07-29T01:00:01Z" }
    )
    guard case .staged = stager.stageCandidate(command: command) else {
      return XCTFail("first staging must succeed")
    }
    let executable = installationRoot.appendingPathComponent(
      "releases/host-0.2.2/release/app/VitalServer Helper.app/Contents/MacOS/VitalServer Helper"
    )
    try Data("tampered".utf8).write(to: executable)

    let result = stager.stageCandidate(command: command)

    guard case .failed(let reason) = result else {
      return XCTFail("tampered slot must be rejected result=\(result)")
    }
    XCTAssertTrue(reason.contains("entryDigestMismatch"))
  }

  func testResumeRejectsExistingSlotWithMissingManifest() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("stager-manifest-missing-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    let installationRoot = root.appendingPathComponent(
      "installed",
      isDirectory: true
    )
    let command = try buildArchive(root: root)
    let stager = HostPlatformReleaseArchiveCandidateStager(
      installationRoot: installationRoot,
      observedAt: { "2026-07-29T01:00:01Z" }
    )
    guard case .staged = stager.stageCandidate(command: command) else {
      return XCTFail("first staging must succeed")
    }
    try FileManager.default.removeItem(
      at: installationRoot.appendingPathComponent(
        "releases/host-0.2.2/release/installation-manifest.json"
      )
    )

    let result = stager.stageCandidate(command: command)

    guard case .failed(let reason) = result else {
      return XCTFail("missing manifest must be rejected result=\(result)")
    }
    XCTAssertTrue(reason.contains("stagedSlotManifestMissing"))
  }

  func testResumeRejectsNonDirectoryDestination() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("stager-notdir-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    let installationRoot = root.appendingPathComponent(
      "installed",
      isDirectory: true
    )
    let command = try buildArchive(root: root)
    try FileManager.default.createDirectory(
      at: installationRoot.appendingPathComponent("releases"),
      withIntermediateDirectories: true
    )
    try Data("not-a-slot".utf8).write(
      to: installationRoot.appendingPathComponent("releases/host-0.2.2")
    )
    let stager = HostPlatformReleaseArchiveCandidateStager(
      installationRoot: installationRoot,
      observedAt: { "2026-07-29T01:00:01Z" }
    )

    let result = stager.stageCandidate(command: command)

    guard case .failed(let reason) = result else {
      return XCTFail("non-directory destination must be rejected result=\(result)")
    }
    XCTAssertTrue(reason.contains("stagedSlotNotDirectory"))
  }

  func testTemporaryOrphanIsRemovedBeforeStaging() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("stager-orphan-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    let installationRoot = root.appendingPathComponent(
      "installed",
      isDirectory: true
    )
    let command = try buildArchive(root: root)
    let orphan = installationRoot.appendingPathComponent(
      ".candidate-\(command.stagingAttemptId)",
      isDirectory: true
    )
    try FileManager.default.createDirectory(
      at: orphan,
      withIntermediateDirectories: true
    )
    try Data("partial".utf8).write(
      to: orphan.appendingPathComponent("partial.txt")
    )
    let stager = HostPlatformReleaseArchiveCandidateStager(
      installationRoot: installationRoot,
      observedAt: { "2026-07-29T01:00:01Z" }
    )

    let result = stager.stageCandidate(command: command)

    guard case .staged = result else {
      return XCTFail("staging after orphan removal must succeed result=\(result)")
    }
    XCTAssertFalse(FileManager.default.fileExists(atPath: orphan.path))
  }

  func testResumeStillRequiresMatchingSourceArchiveDigest() throws {
    let root = FileManager.default.temporaryDirectory
      .appendingPathComponent("stager-source-digest-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    let installationRoot = root.appendingPathComponent(
      "installed",
      isDirectory: true
    )
    let command = try buildArchive(root: root)
    let stager = HostPlatformReleaseArchiveCandidateStager(
      installationRoot: installationRoot,
      observedAt: { "2026-07-29T01:00:01Z" }
    )
    guard case .staged = stager.stageCandidate(command: command) else {
      return XCTFail("first staging must succeed")
    }
    let archiveURL = URL(fileURLWithPath: command.sourceArtifactPath)
    var data = try Data(contentsOf: archiveURL)
    data[data.startIndex] =
      data[data.startIndex] == 0xFF ? 0x00 : 0xFF
    try data.write(to: archiveURL)

    let result = stager.stageCandidate(command: command)

    guard case .failed(let reason) = result else {
      return XCTFail("mismatched source digest must be rejected result=\(result)")
    }
    XCTAssertTrue(reason.contains("entryDigestMismatch"))
  }

  private func makeCommand(
    operationId: String,
    kind: HostPlatformInstallationOperationKind,
    id: String,
    version: String,
    sha256: String,
    slotRelativePath: String,
    sourceArtifactPath: String,
    sourceArtifactSizeBytes: UInt64,
    stagingAttemptId: String
  ) -> HostPlatformInstallationCommand {
    HostPlatformInstallationCommand(
      operationId: operationId,
      kind: kind,
      installationId: "installation-1",
      expectedInstallationRevision: 1,
      targetRelease: HostPlatformRelease(
        id: id,
        version: version,
        sha256: sha256,
        slotRelativePath: slotRelativePath
      ),
      sourceArtifactPath: sourceArtifactPath,
      sourceArtifactSizeBytes: sourceArtifactSizeBytes,
      sourceArtifactMediaType: HostPlatformReleaseArchiveContract.mediaType,
      stagingAttemptId: stagingAttemptId,
      requestedAt: "2026-07-29T01:00:00Z"
    )
  }

  private func buildArchive(
    root: URL,
    extraFiles: [String: Data] = [:],
    omitDeclaredFile: Bool = false,
    executableContent: String = "helper-next",
    releaseId: String = "host-0.2.2",
    releaseVersion: String = "0.2.2",
    slotRelativePath: String = "releases/host-0.2.2"
  ) throws -> HostPlatformInstallationCommand {
    let sourceRoot = root.appendingPathComponent("source")
    let releaseRoot = sourceRoot.appendingPathComponent("release")
    let applicationRelativePath = "app/VitalServer Helper.app"
    let entrypointRelativePath = "Contents/MacOS/VitalServer Helper"
    let infoRelativePath = "Contents/Info.plist"
    let entrypoint = releaseRoot.appendingPathComponent(
      "\(applicationRelativePath)/\(entrypointRelativePath)"
    )
    let info = releaseRoot.appendingPathComponent(
      "\(applicationRelativePath)/\(infoRelativePath)"
    )
    let services = sourceRoot.appendingPathComponent("service-definitions")
    let operatorRoot = sourceRoot.appendingPathComponent("operator-interface")
    for directory in [entrypoint.deletingLastPathComponent(), services, operatorRoot] {
      try FileManager.default.createDirectory(
        at: directory,
        withIntermediateDirectories: true
      )
    }
    let executableData = Data(executableContent.utf8)
    let infoData = Data("<plist/>".utf8)
    let serviceData = Data("vm-plist".utf8)
    let bootstrapData = Data("bootstrap".utf8)
    try executableData.write(to: entrypoint)
    try FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: entrypoint.path
    )
    if !omitDeclaredFile {
      try infoData.write(to: info)
    }
    try serviceData.write(to: services.appendingPathComponent("vm.plist"))
    try bootstrapData.write(
      to: operatorRoot.appendingPathComponent("runtime-console-bootstrap.json")
    )
    let destination = root.appendingPathComponent(
      "installed"
    ).appendingPathComponent(slotRelativePath)
    let manifest: [String: Any] = [
      "schemaVersion": HostPlatformReleaseArchiveContract.manifestSchemaVersion,
      "installationId": "installation-1",
      "release": ["id": releaseId, "version": releaseVersion],
      "releaseCatalogPath": root.appendingPathComponent("installed").path,
      "releaseRootPath": destination.appendingPathComponent("release").path,
      "currentReleaseLinkPath":
        root.appendingPathComponent("installed/current").path,
      "files": [
        [
          "relativePath": "\(applicationRelativePath)/\(entrypointRelativePath)",
          "sha256": sha256(executableData),
          "executable": true,
        ],
        [
          "relativePath": "\(applicationRelativePath)/\(infoRelativePath)",
          "sha256": sha256(infoData),
          "executable": false,
        ],
      ],
      "operatorInterface": [
        "bootstrapConfigurationPath":
          root.appendingPathComponent("control/bootstrap.json").path,
        "bootstrapConfigurationSha256": sha256(bootstrapData),
        "applicationBundlePath":
          root.appendingPathComponent("Applications/VitalServer Helper.app").path,
        "applicationBundleRelativePath": applicationRelativePath,
        "applicationBundleTreeSha256": applicationTreeSHA256([
          (relativePath: entrypointRelativePath, sha256: sha256(executableData)),
          (relativePath: infoRelativePath, sha256: sha256(infoData)),
        ]),
        "applicationBundleEntrypointRelativePath": entrypointRelativePath,
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
            root.appendingPathComponent("stable/vitalserver-host-installation-manager").path,
        ],
        [
          "role": "update-handoff-supervisor",
          "executablePath":
            root.appendingPathComponent("stable/vitalserver-update-handoff-supervisor").path,
          "serviceName": "ai.tirosh.vitalserver.helper.update-handoff-supervisor",
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
      to: releaseRoot.appendingPathComponent("installation-manifest.json")
    )
    for (relativePath, data) in extraFiles {
      let url = sourceRoot.appendingPathComponent(relativePath)
      try FileManager.default.createDirectory(
        at: url.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try data.write(to: url)
    }
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
    return HostPlatformInstallationCommand(
      operationId: "update-archive-1",
      kind: .apply,
      installationId: "installation-1",
      expectedInstallationRevision: 1,
      targetRelease: HostPlatformRelease(
        id: releaseId,
        version: releaseVersion,
        sha256: sha256(archiveData),
        slotRelativePath: slotRelativePath
      ),
      sourceArtifactPath: archive.path,
      sourceArtifactSizeBytes: UInt64(archiveData.count),
      sourceArtifactMediaType: HostPlatformReleaseArchiveContract.mediaType,
      stagingAttemptId: "archive-attempt-1",
      requestedAt: "2026-07-29T01:00:00Z"
    )
  }

  private func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }

  private func applicationTreeSHA256(
    _ entries: [(relativePath: String, sha256: String)]
  ) -> String {
    var digest = SHA256()
    for entry in entries.sorted(by: { $0.relativePath < $1.relativePath }) {
      digest.update(data: Data("regular-file\0".utf8))
      digest.update(data: Data(entry.relativePath.utf8))
      digest.update(data: Data([0]))
      digest.update(data: Data(entry.sha256.lowercased().utf8))
      digest.update(data: Data([0]))
    }
    return digest.finalize().map { String(format: "%02x", $0) }.joined()
  }

  private func run(_ executable: String, _ arguments: [String]) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: executable)
    process.environment = ProcessInfo.processInfo.environment.merging(
      ["COPYFILE_DISABLE": "1"]
    ) { _, explicit in explicit }
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    XCTAssertEqual(process.terminationStatus, 0)
  }
}
