import Contracts
import CryptoKit
import Domain
import Foundation
@testable import HostPlatformLayerEffectExecutorHost
import XCTest

final class HostPlatformLayerEffectExecutorBoundaryTests: XCTestCase {
  func testCorrelatedConfigurationFailureWritesTypedReceipt() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    let request = root.appendingPathComponent("request.json")
    let receipt = root.appendingPathComponent("receipt.json")
    let invocation = ProductUpdateLayerEffectInvocation(
      schemaVersion:
        ProductUpdateExecutionContract.layerEffectInvocationSchemaVersion,
      updateId: "update-typed-failure",
      layer: .hostPlatform,
      effectExecutorId: "helper-host-effect",
      operation: .apply,
      artifactRelativePath: "payload/host.tar.gz",
      artifactPath: root.appendingPathComponent("missing.tar.gz").path,
      artifactSHA256: String(repeating: "a", count: 64),
      artifactSizeBytes: 100,
      artifactMediaType: HostPlatformReleaseArchiveContract.mediaType,
      configurationRelativePath: "config/host.json",
      configurationPath: root.appendingPathComponent("missing.json").path,
      configurationSHA256: String(repeating: "b", count: 64)
    )
    try JSONEncoder().encode(invocation).write(to: request)

    try HostPlatformLayerEffectExecutor.execute(
      arguments: HostPlatformLayerEffectExecutorArguments([
        "execute",
        "--request", request.path,
        "--receipt", receipt.path,
      ])
    )

    let document = try JSONDecoder().decode(
      ProductUpdateLayerEffectReceipt.self,
      from: Data(contentsOf: receipt)
    )
    XCTAssertEqual(document.state, .failed)
    XCTAssertEqual(
      document.issue?.code,
      "host-platform-effect-input-invalid"
    )
    XCTAssertEqual(document.evidence.kind, "host-platform-layer-effect-attempt")
    XCTAssertEqual(
      document.evidence.id,
      "update-typed-failure.host-platform.apply"
    )
  }

  func testUnavailableManagerPreservesUnavailableState() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    let artifact = root.appendingPathComponent("host.tar.gz")
    let artifactData = Data("verified-host-archive".utf8)
    try artifactData.write(to: artifact)
    let configuration = HostPlatformLayerEffectConfiguration(
      schemaVersion: HostPlatformLayerEffectPolicy.configurationSchemaVersion,
      effectExecutorId: "helper-host-effect",
      manager: HostPlatformManagerEndpoint(
        executablePath: root.appendingPathComponent("missing-manager").path,
        databasePath: root.appendingPathComponent("state.sqlite").path,
        installationRootPath: root.appendingPathComponent("installation").path,
        launchctlExecutablePath: "/bin/launchctl",
        exchangeRootPath: root.appendingPathComponent("exchange").path
      ),
      apply: transition(revision: 1, releaseId: "release-2"),
      rollback: transition(revision: 2, releaseId: "release-1")
    )
    let configurationURL = root.appendingPathComponent("configuration.json")
    let configurationData = try JSONEncoder().encode(configuration)
    try configurationData.write(to: configurationURL)
    let request = root.appendingPathComponent("request.json")
    let receipt = root.appendingPathComponent("receipt.json")
    let invocation = ProductUpdateLayerEffectInvocation(
      schemaVersion:
        ProductUpdateExecutionContract.layerEffectInvocationSchemaVersion,
      updateId: "update-manager-unavailable",
      layer: .hostPlatform,
      effectExecutorId: "helper-host-effect",
      operation: .apply,
      artifactRelativePath: "payload/host.tar.gz",
      artifactPath: artifact.path,
      artifactSHA256: digest(artifactData),
      artifactSizeBytes: artifactData.count,
      artifactMediaType: HostPlatformReleaseArchiveContract.mediaType,
      configurationRelativePath: "config/host.json",
      configurationPath: configurationURL.path,
      configurationSHA256: digest(configurationData)
    )
    try JSONEncoder().encode(invocation).write(to: request)

    try HostPlatformLayerEffectExecutor.execute(
      arguments: HostPlatformLayerEffectExecutorArguments([
        "execute",
        "--request", request.path,
        "--receipt", receipt.path,
      ])
    )

    let document = try JSONDecoder().decode(
      ProductUpdateLayerEffectReceipt.self,
      from: Data(contentsOf: receipt)
    )
    XCTAssertEqual(document.state, .unavailable)
    XCTAssertEqual(
      document.issue?.code,
      "host-installation-manager-unavailable"
    )
    XCTAssertEqual(document.issue?.retryable, true)
    XCTAssertEqual(document.issue?.dependency, "host-installation-manager")
    XCTAssertEqual(document.evidence.kind, "host-platform-layer-effect-attempt")
  }

  func testInvalidInvocationDoesNotWriteUncorrelatedReceipt() throws {
    let root = FileManager.default.temporaryDirectory.appendingPathComponent(
      UUID().uuidString,
      isDirectory: true
    )
    defer { try? FileManager.default.removeItem(at: root) }
    try FileManager.default.createDirectory(
      at: root,
      withIntermediateDirectories: true
    )
    let request = root.appendingPathComponent("request.json")
    let receipt = root.appendingPathComponent("receipt.json")
    try Data("{\"unknown\":true}".utf8).write(to: request)

    XCTAssertThrowsError(
      try HostPlatformLayerEffectExecutor.execute(
        arguments: HostPlatformLayerEffectExecutorArguments([
          "execute",
          "--request", request.path,
          "--receipt", receipt.path,
        ])
      )
    )
    XCTAssertFalse(
      FileManager.default.fileExists(atPath: receipt.path)
    )
  }

  private func transition(
    revision: Int,
    releaseId: String
  ) -> HostPlatformLayerTransition {
    HostPlatformLayerTransition(
      installationId: "installation-1",
      expectedInstallationRevision: revision,
      targetReleaseId: releaseId,
      targetReleaseVersion: "0.2.2",
      targetSlotRelativePath: "releases/\(releaseId)"
    )
  }

  private func digest(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
  }
}
