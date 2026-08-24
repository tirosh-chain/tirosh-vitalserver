import Contracts
import Domain
import XCTest

final class HostPlatformLayerEffectPolicyTests: XCTestCase {
  func testApplyProducesExplicitManagerCommandForVerifiedHelperArchive() throws {
    let invocation = makeInvocation()

    let command = try HostPlatformLayerEffectPolicy.makeManagerCommand(
      invocation: invocation,
      configuration: makeConfiguration(),
      requestedAt: "2026-07-29T02:00:00Z"
    )

    XCTAssertEqual(command.operationId, "update-22.host-platform.apply")
    XCTAssertEqual(command.kind, .apply)
    XCTAssertEqual(command.installationId, "helper-installation")
    XCTAssertEqual(command.expectedInstallationRevision, 4)
    XCTAssertEqual(command.targetRelease.id, "helper-0.2.2")
    XCTAssertEqual(command.sourceArtifactSizeBytes, 4_096)
    XCTAssertEqual(
      command.sourceArtifactMediaType,
      HostPlatformReleaseArchiveContract.mediaType
    )
  }

  func testRuntimePlatformArchiveMediaCannotCrossHelperBoundary() {
    let invocation = makeInvocation(
      mediaType:
        "application/vnd.tirosh.vitalserver.host-platform-release+tar+gzip"
    )

    XCTAssertThrowsError(
      try HostPlatformLayerEffectPolicy.validate(
        invocation: invocation,
        configuration: makeConfiguration()
      )
    ) { error in
      XCTAssertEqual(
        error as? HostPlatformLayerEffectPolicyError,
        .invalidInvocation
      )
    }
  }

  private func makeInvocation(
    mediaType: String = HostPlatformReleaseArchiveContract.mediaType
  ) -> ProductUpdateLayerEffectInvocation {
    ProductUpdateLayerEffectInvocation(
      schemaVersion:
        ProductUpdateExecutionContract.layerEffectInvocationSchemaVersion,
      updateId: "update-22",
      layer: .hostPlatform,
      effectExecutorId: "helper-host-effect",
      operation: .apply,
      guestControlBaseURL: "http://192.168.64.3:18330/",
      artifactRelativePath: "payload/helper-host.tar.gz",
      artifactPath: "/updates/helper-host.tar.gz",
      artifactSHA256: String(repeating: "a", count: 64),
      artifactSizeBytes: 4_096,
      artifactMediaType: mediaType,
      configurationRelativePath: "config/helper-host.json",
      configurationPath: "/updates/helper-host.json",
      configurationSHA256: String(repeating: "b", count: 64)
    )
  }

  private func makeConfiguration() -> HostPlatformLayerEffectConfiguration {
    HostPlatformLayerEffectConfiguration(
      schemaVersion:
        HostPlatformLayerEffectPolicy.configurationSchemaVersion,
      effectExecutorId: "helper-host-effect",
      manager: HostPlatformManagerEndpoint(
        executablePath:
          "/Library/Application Support/VitalServerHelper/update-manager/bin/vitalserver-host-installation-manager",
        databasePath:
          "/Library/Application Support/VitalServerHelper/update-manager/state.sqlite",
        installationRootPath:
          "/Library/Application Support/VitalServerHelper/host-platform",
        launchctlExecutablePath: "/bin/launchctl",
        exchangeRootPath:
          "/Library/Application Support/VitalServerHelper/update-manager/exchange"
      ),
      apply: HostPlatformLayerTransition(
        installationId: "helper-installation",
        expectedInstallationRevision: 4,
        targetReleaseId: "helper-0.2.2",
        targetReleaseVersion: "0.2.2",
        targetSlotRelativePath: "releases/helper-0.2.2"
      ),
      rollback: HostPlatformLayerTransition(
        installationId: "helper-installation",
        expectedInstallationRevision: 5,
        targetReleaseId: "helper-0.2.1",
        targetReleaseVersion: "0.2.1",
        targetSlotRelativePath: "releases/helper-0.2.1"
      )
    )
  }
}
