import Application
import Contracts
import CryptoKit
import Foundation
import OutboundAdapters
import XCTest

final class MacOSHostPlatformReleaseServiceReconcilerTests: XCTestCase {
  func testQuiesceTreatsAlreadyNotLoadedBootoutAsDesiredOutcome() throws {
    let fixture = try stageReleases()
    defer { fixture.cleanup() }
    let launchctl = fixture.writeLaunchctl(
      """
      #!/bin/sh
      if [ "$1" = "bootout" ]; then
        printf '%s\\n' 'Could not find service' >&2
        exit 113
      fi
      if [ "$1" = "print" ]; then
        printf '%s\\n' 'Could not find service' >&2
        exit 113
      fi
      exit 0
      """
    )
    let reconciler = MacOSHostPlatformReleaseServiceReconciler(
      installationRoot: fixture.installationRoot,
      launchctlURL: launchctl
    )

    let observations = try reconciler.quiesceServices(
      fixture.target.replaceableServices
    )

    XCTAssertEqual(observations.map(\.action), [.bootout, .print])
    XCTAssertEqual(observations.first?.outcome, .alreadyNotLoaded)
    XCTAssertEqual(observations.last?.outcome, .notLoaded)
  }

  func testQuiesceSettlesEachServiceBeforeStoppingTheNext() throws {
    let fixture = try stageReleases(serviceRoles: ["vm", "platform-agent"])
    defer { fixture.cleanup() }
    let log = fixture.extraFile("launchctl.log")
    let printCounts = fixture.extraFile("print-counts")
    try FileManager.default.createDirectory(
      at: printCounts,
      withIntermediateDirectories: true
    )
    let launchctl = fixture.writeLaunchctl(
      """
      #!/bin/sh
      printf '%s\\n' "$*" >> "\(log.path)"
      if [ "$1" = "bootout" ]; then
        exit 0
      fi
      if [ "$1" = "print" ]; then
        service="$2"
        count_file="\(printCounts.path)/$(basename "$service")"
        count=0
        if [ -f "$count_file" ]; then
          count="$(cat "$count_file")"
        fi
        count=$((count + 1))
        printf '%s\\n' "$count" > "$count_file"
        if [ "$count" -eq 1 ] && [ "$service" = "system/ai.tirosh.vitalserver.helper.platform-agent" ]; then
          exit 0
        fi
        printf '%s\\n' 'Could not find service' >&2
        exit 113
      fi
      exit 1
      """
    )
    let reconciler = MacOSHostPlatformReleaseServiceReconciler(
      installationRoot: fixture.installationRoot,
      launchctlURL: launchctl,
      serviceStopPollIntervalSeconds: 0
    )

    let observations = try reconciler.quiesceServices(
      fixture.target.replaceableServices
    )

    let recorded = try String(contentsOf: log, encoding: .utf8)
      .split(whereSeparator: \.isNewline)
      .map(String.init)
    XCTAssertEqual(
      recorded,
      [
        "bootout system/ai.tirosh.vitalserver.helper.platform-agent",
        "print system/ai.tirosh.vitalserver.helper.platform-agent",
        "print system/ai.tirosh.vitalserver.helper.platform-agent",
        "bootout system/ai.tirosh.vitalserver.helper.vm",
        "print system/ai.tirosh.vitalserver.helper.vm",
      ]
    )
    XCTAssertEqual(
      observations.map { "\($0.serviceName):\($0.action.rawValue):\($0.outcome.rawValue)" },
      [
        "ai.tirosh.vitalserver.helper.platform-agent:bootout:accepted",
        "ai.tirosh.vitalserver.helper.platform-agent:print:not-loaded",
        "ai.tirosh.vitalserver.helper.vm:bootout:accepted",
        "ai.tirosh.vitalserver.helper.vm:print:not-loaded",
      ]
    )
  }

  func testQuiesceGivesVMTheDeclaredLongStopWindow() throws {
    let fixture = try stageReleases(serviceRoles: ["vm"])
    defer { fixture.cleanup() }
    let launchctl = fixture.writeLaunchctl(
      """
      #!/bin/sh
      if [ "$1" = "bootout" ]; then
        exit 0
      fi
      if [ "$1" = "print" ]; then
        exit 0
      fi
      exit 1
      """
    )
    let clock = SettlementClock(now: Date(timeIntervalSince1970: 1_000))
    let reconciler = MacOSHostPlatformReleaseServiceReconciler(
      installationRoot: fixture.installationRoot,
      launchctlURL: launchctl,
      now: { clock.now },
      sleep: { clock.now.addTimeInterval($0) },
      vmStopTimeoutSeconds: 900,
      serviceStopTimeoutSeconds: 30,
      serviceStopPollIntervalSeconds: 30
    )

    XCTAssertThrowsError(
      try reconciler.quiesceServices(fixture.target.replaceableServices)
    ) { error in
      XCTAssertEqual(
        error as? MacOSHostPlatformReleaseServiceReconciliationError,
        .serviceStopSettlementTimedOut(
          service: "ai.tirosh.vitalserver.helper.vm",
          timeoutSeconds: 900
        )
      )
    }
    XCTAssertEqual(clock.now.timeIntervalSince1970, 1_000 + 900)
  }

  func testQuiesceKeepsTimeoutPermissionAndFailedDistinct() throws {
    let fixture = try stageReleases()
    defer { fixture.cleanup() }

    let timeoutLaunchctl = fixture.writeLaunchctl(
      """
      #!/bin/sh
      if [ "$1" = "bootout" ]; then
        exit 0
      fi
      exit 0
      """
    )
    let clock = SettlementClock(now: Date(timeIntervalSince1970: 1_000))
    XCTAssertThrowsError(
      try MacOSHostPlatformReleaseServiceReconciler(
        installationRoot: fixture.installationRoot,
        launchctlURL: timeoutLaunchctl,
        now: { clock.now },
        sleep: { clock.now.addTimeInterval($0) },
        serviceStopTimeoutSeconds: 30,
        serviceStopPollIntervalSeconds: 30
      ).quiesceServices(fixture.target.replaceableServices)
    ) { error in
      XCTAssertEqual(
        error as? MacOSHostPlatformReleaseServiceReconciliationError,
        .serviceStopSettlementTimedOut(
          service: fixture.target.replaceableServices[0].name,
          timeoutSeconds: 30
        )
      )
    }

    let permissionLaunchctl = fixture.writeLaunchctl(
      """
      #!/bin/sh
      exit 1
      """
    )
    XCTAssertThrowsError(
      try MacOSHostPlatformReleaseServiceReconciler(
        installationRoot: fixture.installationRoot,
        launchctlURL: permissionLaunchctl
      ).quiesceServices(fixture.target.replaceableServices)
    ) { error in
      guard case .serviceCommandFailed(_, _, let status, _) =
        error as? MacOSHostPlatformReleaseServiceReconciliationError
      else {
        return XCTFail("permission must stay a command failure error=\(error)")
      }
      XCTAssertEqual(status, 1)
    }

    let failedLaunchctl = fixture.writeLaunchctl(
      """
      #!/bin/sh
      printf '%s\\n' 'unexpected failure' >&2
      exit 42
      """
    )
    XCTAssertThrowsError(
      try MacOSHostPlatformReleaseServiceReconciler(
        installationRoot: fixture.installationRoot,
        launchctlURL: failedLaunchctl
      ).quiesceServices(fixture.target.replaceableServices)
    ) { error in
      guard case .serviceCommandFailed(_, _, let status, let reason) =
        error as? MacOSHostPlatformReleaseServiceReconciliationError
      else {
        return XCTFail("unknown exit must stay failed error=\(error)")
      }
      XCTAssertEqual(status, 42)
      XCTAssertEqual(reason, "unexpected failure")
    }
  }

  func testLoadedProofIsNotInferredFromStderrText() throws {
    let fixture = try stageReleases()
    defer { fixture.cleanup() }
    let launchctl = fixture.writeLaunchctl(
      """
      #!/bin/sh
      printf '%s\\n' 'Could not find service' >&2
      exit 0
      """
    )
    let reconciler = MacOSHostPlatformReleaseServiceReconciler(
      installationRoot: fixture.installationRoot,
      launchctlURL: launchctl
    )

    let states = reconciler.readServiceStates(
      fixture.target.replaceableServices
    )
    XCTAssertEqual(states.first?.outcome, .loaded)
  }

  func testLoadServicesFailsWhenTargetServiceImmediatelyUnloads() throws {
    let fixture = try stageReleases()
    defer { fixture.cleanup() }
    let launchctl = fixture.writeLaunchctl(
      """
      #!/bin/sh
      if [ "$1" = "bootstrap" ]; then
        exit 0
      fi
      if [ "$1" = "print" ]; then
        printf '%s\\n' 'Could not find service' >&2
        exit 113
      fi
      exit 0
      """
    )
    let reconciler = MacOSHostPlatformReleaseServiceReconciler(
      installationRoot: fixture.installationRoot,
      launchctlURL: launchctl
    )

    XCTAssertThrowsError(
      try reconciler.loadServices(fixture.target.replaceableServices)
    ) { error in
      XCTAssertEqual(
        error as? MacOSHostPlatformReleaseServiceReconciliationError,
        .serviceLoadedProofFailed(
          service: fixture.target.replaceableServices[0].name,
          reason: "bootstrap accepted but service is not loaded"
        )
      )
    }
  }

  func testLoadServicesSkipsAlreadyLoadedService() throws {
    let fixture = try stageReleases()
    defer { fixture.cleanup() }
    let invocationCount = fixture.extraFile("bootstrap-count")
    let launchctl = fixture.writeLaunchctl(
      """
      #!/bin/sh
      if [ "$1" = "print" ]; then
        exit 0
      fi
      if [ "$1" = "bootstrap" ]; then
        count=0
        if [ -f "\(invocationCount.path)" ]; then
          count="$(cat "\(invocationCount.path)")"
        fi
        count=$((count + 1))
        printf '%s\\n' "$count" > "\(invocationCount.path)"
      fi
      exit 0
      """
    )
    let reconciler = MacOSHostPlatformReleaseServiceReconciler(
      installationRoot: fixture.installationRoot,
      launchctlURL: launchctl
    )

    let observations = try reconciler.loadServices(
      fixture.target.replaceableServices
    )

    XCTAssertEqual(observations.map(\.action), [.print])
    XCTAssertEqual(observations.first?.outcome, .loaded)
    XCTAssertEqual(
      try? String(contentsOf: invocationCount, encoding: .utf8)
        .trimmingCharacters(in: .whitespacesAndNewlines),
      nil
    )
  }

  func testExitCodeDistinguishesPermissionDeniedFromReadFailure() throws {
    let fixture = try stageReleases()
    defer { fixture.cleanup() }
    let launchctl = fixture.writeLaunchctl(
      """
      #!/bin/sh
      if [ "$2" = "system/permission" ]; then
        printf '%s\\n' 'Operation not permitted' >&2
        exit 1
      fi
      printf '%s\\n' 'unexpected failure' >&2
      exit 42
      """
    )
    let reconciler = MacOSHostPlatformReleaseServiceReconciler(
      installationRoot: fixture.installationRoot,
      launchctlURL: launchctl
    )
    var permission = fixture.target.replaceableServices[0]
    permission = HostPlatformRequiredService(
      role: permission.role,
      manager: permission.manager,
      name: "permission",
      definitionPath: permission.definitionPath,
      definitionSha256: permission.definitionSha256
    )
    let denied = reconciler.readServiceStates([permission])
    XCTAssertEqual(denied.first?.outcome, .permissionDenied)

    let readFailure = reconciler.readServiceStates(
      fixture.target.replaceableServices
    )
    XCTAssertEqual(readFailure.first?.outcome, .failed)
  }

  func testExitContractIsStableAcrossLocales() throws {
    let fixture = try stageReleases()
    defer { fixture.cleanup() }
    let launchctl = fixture.writeLaunchctl(
      """
      #!/bin/sh
      printf '%s\\n' '서비스를 찾을 수 없습니다' >&2
      exit 113
      """
    )
    let reconciler = MacOSHostPlatformReleaseServiceReconciler(
      installationRoot: fixture.installationRoot,
      launchctlURL: launchctl
    )

    let states = reconciler.readServiceStates(
      fixture.target.replaceableServices
    )

    XCTAssertEqual(states.first?.outcome, .notLoaded)
  }

  func testActivateTargetIsIdempotentWhenAlreadyResolvedToTarget() throws {
    let fixture = try stageReleases()
    defer { fixture.cleanup() }
    // Current link already resolves to target before activation.
    try FileManager.default.removeItem(
      at: fixture.installationRoot.appendingPathComponent("current")
    )
    try FileManager.default.createSymbolicLink(
      at: fixture.installationRoot.appendingPathComponent("current"),
      withDestinationURL: URL(
        fileURLWithPath: fixture.target.releaseRootPath,
        isDirectory: true
      )
    )
    let launchctl = fixture.writeLaunchctl("#!/bin/sh\nexit 0\n")
    let reconciler = MacOSHostPlatformReleaseServiceReconciler(
      installationRoot: fixture.installationRoot,
      launchctlURL: launchctl
    )

    let resolved = try reconciler.activateTarget(fixture.target)

    XCTAssertEqual(resolved, fixture.target.releaseRootPath)
  }

  func testPublishRejectsUndeclaredCandidateFile() throws {
    let fixture = try stageReleases()
    defer { fixture.cleanup() }
    let undeclared = URL(
      fileURLWithPath: fixture.target.releaseRootPath,
      isDirectory: true
    ).appendingPathComponent("undeclared.txt")
    try Data("extra".utf8).write(to: undeclared)
    let launchctl = fixture.writeLaunchctl("#!/bin/sh\nexit 0\n")
    let reconciler = MacOSHostPlatformReleaseServiceReconciler(
      installationRoot: fixture.installationRoot,
      launchctlURL: launchctl
    )

    XCTAssertThrowsError(
      try reconciler.publishInterfaces(fixture.target)
    ) { error in
      guard case .closureViolation = error as?
        MacOSHostPlatformReleaseServiceReconciliationError
      else {
        return XCTFail("unexpected error \(error)")
      }
    }
  }
}

private final class SettlementClock: @unchecked Sendable {
  var now: Date

  init(now: Date) {
    self.now = now
  }
}

private struct ReconcilerFixture {
  let root: URL
  let installationRoot: URL
  let application: URL
  let bootstrap: URL
  let serviceDefinition: URL
  let previous: HostPlatformReleaseArchiveManifest
  let target: HostPlatformReleaseArchiveManifest

  func cleanup() {
    try? FileManager.default.removeItem(at: root)
  }

  func extraFile(_ name: String) -> URL {
    root.appendingPathComponent(name)
  }

  func writeLaunchctl(_ script: String) -> URL {
    let launchctl = root.appendingPathComponent("launchctl")
    try! Data(script.utf8).write(to: launchctl)
    try! FileManager.default.setAttributes(
      [.posixPermissions: 0o755],
      ofItemAtPath: launchctl.path
    )
    return launchctl
  }
}

private func stageReleases(
  serviceRoles: [String] = ["platform-agent"]
) throws -> ReconcilerFixture {
  let root = temporaryDirectory()
  let installationRoot = root.appendingPathComponent("host-platform")
  let application = root.appendingPathComponent(
    "Applications/VitalServer Helper.app"
  )
  let bootstrap = root.appendingPathComponent(
    "config/runtime-console-bootstrap.json"
  )
  let serviceDefinition = root.appendingPathComponent(
    "LaunchDaemons/platform-agent.plist"
  )
  let previous = try stageRelease(
    id: "helper-0.2.2",
    installationRoot: installationRoot,
    application: application,
    bootstrap: bootstrap,
    serviceDefinition: serviceDefinition,
    serviceRoles: serviceRoles
  )
  let target = try stageRelease(
    id: "helper-0.2.3",
    installationRoot: installationRoot,
    application: application,
    bootstrap: bootstrap,
    serviceDefinition: serviceDefinition,
    serviceRoles: serviceRoles
  )
  try FileManager.default.createDirectory(
    at: application.deletingLastPathComponent(),
    withIntermediateDirectories: true
  )
  let current = installationRoot.appendingPathComponent("current")
  try FileManager.default.createSymbolicLink(
    at: current,
    withDestinationURL: URL(
      fileURLWithPath: previous.releaseRootPath,
      isDirectory: true
    )
  )
  return ReconcilerFixture(
    root: root,
    installationRoot: installationRoot,
    application: application,
    bootstrap: bootstrap,
    serviceDefinition: serviceDefinition,
    previous: previous,
    target: target
  )
}

private func stageRelease(
  id: String,
  installationRoot: URL,
  application: URL,
  bootstrap: URL,
  serviceDefinition: URL,
  serviceRoles: [String] = ["platform-agent"]
) throws -> HostPlatformReleaseArchiveManifest {
  let releaseRoot = installationRoot.appendingPathComponent(
    "releases/\(id)/release",
    isDirectory: true
  )
  let candidateRoot = releaseRoot.deletingLastPathComponent()
  let applicationRelativePath = "app/VitalServer Helper.app"
  let applicationRoot = releaseRoot.appendingPathComponent(
    applicationRelativePath,
    isDirectory: true
  )
  let executableRelativePath = "Contents/MacOS/VitalServer Helper"
  let infoRelativePath = "Contents/Info.plist"
  let executable = applicationRoot.appendingPathComponent(executableRelativePath)
  let info = applicationRoot.appendingPathComponent(infoRelativePath)
  let serviceSources = serviceRoles.map {
    candidateRoot.appendingPathComponent("service-definitions/\($0).plist")
  }
  let bootstrapSource = candidateRoot.appendingPathComponent(
    "operator-interface/runtime-console-bootstrap.json"
  )
  for directory in [
    executable.deletingLastPathComponent(),
    info.deletingLastPathComponent(),
    serviceSources[0].deletingLastPathComponent(),
    bootstrapSource.deletingLastPathComponent(),
  ] {
    try FileManager.default.createDirectory(
      at: directory,
      withIntermediateDirectories: true
    )
  }
  let executableData = Data("executable-\(id)".utf8)
  let infoData = Data("<plist></plist>".utf8)
  let bootstrapData = Data("bootstrap-\(id)".utf8)
  try executableData.write(to: executable)
  try infoData.write(to: info)
  let serviceData = serviceRoles.map { Data("service-\($0)-\(id)".utf8) }
  for (source, data) in zip(serviceSources, serviceData) {
    try data.write(to: source)
  }
  try bootstrapData.write(to: bootstrapSource)
  try FileManager.default.setAttributes(
    [.posixPermissions: 0o755],
    ofItemAtPath: executable.path
  )
  let files: [[String: Any]] = [
    [
      "relativePath": "\(applicationRelativePath)/\(executableRelativePath)",
      "sha256": sha256(executableData),
      "executable": true,
    ],
    [
      "relativePath": "\(applicationRelativePath)/\(infoRelativePath)",
      "sha256": sha256(infoData),
      "executable": false,
    ],
  ]
  let manifest: [String: Any] = [
    "schemaVersion": HostPlatformReleaseArchiveContract.manifestSchemaVersion,
    "installationId": "installation-1",
    "release": ["id": id, "version": "0.2.2"],
    "releaseCatalogPath": installationRoot.path,
    "releaseRootPath": releaseRoot.path,
    "currentReleaseLinkPath": installationRoot.appendingPathComponent("current").path,
    "files": files,
    "operatorInterface": [
      "bootstrapConfigurationPath": bootstrap.path,
      "bootstrapConfigurationSha256": sha256(bootstrapData),
      "applicationBundlePath": application.path,
      "applicationBundleRelativePath": applicationRelativePath,
      "applicationBundleTreeSha256": String(repeating: "c", count: 64),
      "applicationBundleEntrypointRelativePath": executableRelativePath,
    ],
    "replaceableServices": serviceRoles.enumerated().map { index, role in
      [
        "role": role,
        "manager": "launchd",
        "name": "ai.tirosh.vitalserver.helper.\(role)",
        "definitionPath":
          index == 0
          ? serviceDefinition.path
          : serviceDefinition.deletingLastPathComponent()
            .appendingPathComponent("\(role).plist").path,
        "definitionSha256": sha256(serviceData[index]),
      ]
    },
    "stableComponents": [
      [
        "role": "host-installation-manager",
        "executablePath":
          application.deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("bin/vitalserver-host-installation-manager").path,
      ],
      [
        "role": "update-handoff-supervisor",
        "executablePath":
          application.deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("bin/vitalserver-update-handoff-supervisor").path,
        "serviceName": "ai.tirosh.vitalserver.helper.update-handoff-supervisor",
      ],
    ],
    "mutableStores": [[
      "id": "runtime-state",
      "path": application.deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("data").path,
      "kind": "directory",
      "owner": "vitalserver-helper",
      "retention": "preserve-by-default",
    ]],
  ]
  let manifestData = try JSONSerialization.data(
    withJSONObject: manifest,
    options: [.sortedKeys]
  )
  try manifestData.write(
    to: releaseRoot.appendingPathComponent("installation-manifest.json")
  )
  return try JSONDecoder().decode(
    HostPlatformReleaseArchiveManifest.self,
    from: manifestData
  )
}

private func sha256(_ data: Data) -> String {
  SHA256.hash(data: data).map {
    String(format: "%02x", $0)
  }.joined()
}

private func temporaryDirectory() -> URL {
  let directory = FileManager.default.temporaryDirectory
    .appendingPathComponent(
      "host-platform-reconciler-\(UUID().uuidString)",
      isDirectory: true
    )
  try! FileManager.default.createDirectory(
    at: directory,
    withIntermediateDirectories: true
  )
  return directory
}
