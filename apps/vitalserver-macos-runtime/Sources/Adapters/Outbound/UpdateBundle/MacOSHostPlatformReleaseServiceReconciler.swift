import Application
import Contracts
import CryptoKit
import Foundation

public enum MacOSHostPlatformReleaseServiceReconciliationError:
  Error,
  Equatable,
  Sendable
{
  case manifestReadFailed(path: String, reason: String)
  case manifestMismatch(String)
  case activeReleaseMismatch(expected: String, actual: String)
  case immutableEntryInvalid(path: String, reason: String)
  case serviceCommandFailed(action: String, service: String, status: Int32)
  case publicationFailed(path: String, reason: String)
  case activationFailed(String)
  case compensationFailed(effect: String, compensation: String)
}

public struct MacOSHostPlatformReleaseServiceReconciler:
  HostPlatformServiceReconciling,
  @unchecked Sendable
{
  public let installationRoot: URL
  public let launchctlURL: URL
  private let observedAt: @Sendable () -> String
  private let processFactory: () -> Process

  public init(
    installationRoot: URL,
    launchctlURL: URL = URL(fileURLWithPath: "/bin/launchctl"),
    observedAt: @escaping @Sendable () -> String = {
      ISO8601DateFormatter().string(from: Date())
    },
    processFactory: @escaping () -> Process = Process.init
  ) {
    self.installationRoot = installationRoot.standardizedFileURL
    self.launchctlURL = launchctlURL
    self.observedAt = observedAt
    self.processFactory = processFactory
  }

  public func reconcileServices(
    request: HostPlatformServiceReconciliationRequest
  ) -> HostPlatformServiceReconciliationResult {
    do {
      let previous = try loadAndVerify(
        request.previousRelease,
        installationId: request.installationId
      )
      let target = try loadAndVerify(
        request.targetRelease,
        installationId: request.installationId
      )
      try validateTopology(previous: previous, target: target)
      try proveActive(previous)
      do {
        try quiesce(previous)
        try publishServiceDefinitions(target)
        try publishOperatorBootstrap(target)
        try activate(target)
        try start(target)
      } catch {
        do {
          try publishServiceDefinitions(previous)
          try publishOperatorBootstrap(previous)
          try activate(previous)
          try start(previous)
        } catch let compensation {
          throw
            MacOSHostPlatformReleaseServiceReconciliationError
            .compensationFailed(
              effect: String(describing: error),
              compensation: String(describing: compensation)
            )
        }
        throw error
      }
      return .completed(receipt(request, outcome: .succeeded, reason: nil))
    } catch {
      return .completed(
        receipt(
          request,
          outcome: .failed,
          reason: String(describing: error)
        )
      )
    }
  }

  private func loadAndVerify(
    _ release: HostPlatformRelease,
    installationId: String
  ) throws -> HostPlatformReleaseArchiveManifest {
    let candidateRoot = try candidateRoot(for: release)
    let releaseRoot = candidateRoot.appendingPathComponent(
      "release",
      isDirectory: true
    )
    let manifestURL = releaseRoot.appendingPathComponent(
      "installation-manifest.json"
    )
    let manifest: HostPlatformReleaseArchiveManifest
    do {
      let data = try Data(contentsOf: manifestURL)
      guard data.count <= 1_048_576 else {
        throw CocoaError(.fileReadTooLarge)
      }
      manifest = try JSONDecoder().decode(
        HostPlatformReleaseArchiveManifest.self,
        from: data
      )
    } catch {
      throw MacOSHostPlatformReleaseServiceReconciliationError
        .manifestReadFailed(
          path: manifestURL.path,
          reason: String(describing: error)
        )
    }
    guard manifest.schemaVersion
        == HostPlatformReleaseArchiveContract.manifestSchemaVersion,
      manifest.installationId == installationId,
      manifest.release.id == release.id,
      manifest.release.version == release.version,
      manifest.releaseCatalogPath == installationRoot.path,
      manifest.releaseRootPath == releaseRoot.path,
      manifest.currentReleaseLinkPath
        == installationRoot.appendingPathComponent("current").path
    else {
      throw MacOSHostPlatformReleaseServiceReconciliationError
        .manifestMismatch("release \(release.id) identity or layout differs")
    }
    for entry in manifest.files {
      try verify(
        releaseRoot.appendingPathComponent(entry.relativePath),
        expected: entry.sha256
      )
    }
    let operatorSource = candidateRoot.appendingPathComponent(
      "operator-interface/runtime-console-bootstrap.json"
    )
    try verify(
      operatorSource,
      expected: manifest.operatorInterface.bootstrapConfigurationSha256
    )
    for service in manifest.replaceableServices {
      try verify(
        candidateRoot.appendingPathComponent(
          "service-definitions/\(service.role).plist"
        ),
        expected: service.definitionSha256
      )
    }
    return manifest
  }

  private func validateTopology(
    previous: HostPlatformReleaseArchiveManifest,
    target: HostPlatformReleaseArchiveManifest
  ) throws {
    let previousServices = previous.replaceableServices.map {
      "\($0.role)|\($0.manager)|\($0.name)|\($0.definitionPath)"
    }
    let targetServices = target.replaceableServices.map {
      "\($0.role)|\($0.manager)|\($0.name)|\($0.definitionPath)"
    }
    let previousStores = previous.mutableStores.map {
      "\($0.id)|\($0.path)|\($0.kind)|\($0.owner)|\($0.retention)"
    }
    let targetStores = target.mutableStores.map {
      "\($0.id)|\($0.path)|\($0.kind)|\($0.owner)|\($0.retention)"
    }
    let stableRoles = Set(target.stableComponents.map(\.role))
    let replaceableRoles = Set(target.replaceableServices.map(\.role))
    guard previous.installationId == target.installationId,
      previous.releaseCatalogPath == target.releaseCatalogPath,
      previous.currentReleaseLinkPath == target.currentReleaseLinkPath,
      previous.operatorInterface.bootstrapConfigurationPath
        == target.operatorInterface.bootstrapConfigurationPath,
      previous.operatorInterface.applicationBundlePath
        == target.operatorInterface.applicationBundlePath,
      previous.operatorInterface.applicationBundleRelativePath
        == target.operatorInterface.applicationBundleRelativePath,
      previous.operatorInterface.applicationBundleEntrypointRelativePath
        == target.operatorInterface.applicationBundleEntrypointRelativePath,
      previous.stableComponents == target.stableComponents,
      stableRoles
        == Set([
          "host-installation-manager",
          "update-handoff-supervisor",
        ]),
      stableRoles.isDisjoint(with: replaceableRoles),
      previousServices == targetServices,
      previousStores == targetStores
    else {
      throw MacOSHostPlatformReleaseServiceReconciliationError
        .manifestMismatch(
          "candidate changes stable installation, service, or mutable-store topology"
        )
    }
    try proveApplicationReference(previous)
  }

  private func proveApplicationReference(
    _ manifest: HostPlatformReleaseArchiveManifest
  ) throws {
    let application = URL(
      fileURLWithPath: manifest.operatorInterface.applicationBundlePath
    )
    let values = try application.resourceValues(forKeys: [.isSymbolicLinkKey])
    guard values.isSymbolicLink == true else {
      throw MacOSHostPlatformReleaseServiceReconciliationError
        .manifestMismatch("operator application reference is not a symlink")
    }
    let declaredTarget =
      URL(fileURLWithPath: manifest.currentReleaseLinkPath)
      .appendingPathComponent(
        manifest.operatorInterface.applicationBundleRelativePath
      ).standardizedFileURL
    let actualTarget = URL(
      fileURLWithPath: try FileManager.default.destinationOfSymbolicLink(
        atPath: application.path
      ),
      relativeTo: application.deletingLastPathComponent()
    ).standardizedFileURL
    guard actualTarget.path == declaredTarget.path else {
      throw MacOSHostPlatformReleaseServiceReconciliationError
        .manifestMismatch("operator application reference target differs")
    }
  }

  private func proveActive(
    _ manifest: HostPlatformReleaseArchiveManifest
  ) throws {
    let current = URL(
      fileURLWithPath: manifest.currentReleaseLinkPath
    )
    let values = try current.resourceValues(forKeys: [.isSymbolicLinkKey])
    guard values.isSymbolicLink == true else {
      throw MacOSHostPlatformReleaseServiceReconciliationError
        .activeReleaseMismatch(expected: manifest.release.id, actual: "not-symlink")
    }
    let resolved = try URL(
      fileURLWithPath: FileManager.default.destinationOfSymbolicLink(
        atPath: current.path
      ),
      relativeTo: current.deletingLastPathComponent()
    ).standardizedFileURL
    guard resolved.path == manifest.releaseRootPath else {
      throw MacOSHostPlatformReleaseServiceReconciliationError
        .activeReleaseMismatch(
          expected: manifest.releaseRootPath,
          actual: resolved.path
        )
    }
  }

  private func quiesce(
    _ manifest: HostPlatformReleaseArchiveManifest
  ) throws {
    for service in manifest.replaceableServices.reversed() {
      try runLaunchctl(
        ["bootout", "system/\(service.name)"],
        action: "bootout",
        service: service.name
      )
    }
  }

  private func start(
    _ manifest: HostPlatformReleaseArchiveManifest
  ) throws {
    for service in manifest.replaceableServices {
      try runLaunchctl(
        ["bootstrap", "system", service.definitionPath],
        action: "bootstrap",
        service: service.name
      )
    }
  }

  private func publishServiceDefinitions(
    _ manifest: HostPlatformReleaseArchiveManifest
  ) throws {
    let candidateRoot = try candidateRoot(
      releaseId: manifest.release.id,
      releaseRootPath: manifest.releaseRootPath
    )
    for service in manifest.replaceableServices {
      let source = candidateRoot.appendingPathComponent(
        "service-definitions/\(service.role).plist"
      )
      try publish(source: source, destinationPath: service.definitionPath)
    }
  }

  private func publishOperatorBootstrap(
    _ manifest: HostPlatformReleaseArchiveManifest
  ) throws {
    let candidateRoot = try candidateRoot(
      releaseId: manifest.release.id,
      releaseRootPath: manifest.releaseRootPath
    )
    try publish(
      source: candidateRoot.appendingPathComponent(
        "operator-interface/runtime-console-bootstrap.json"
      ),
      destinationPath:
        manifest.operatorInterface.bootstrapConfigurationPath
    )
  }

  private func activate(
    _ manifest: HostPlatformReleaseArchiveManifest
  ) throws {
    let current = URL(
      fileURLWithPath: manifest.currentReleaseLinkPath
    )
    let temporary = URL(
      fileURLWithPath:
        "\(current.path).activating-\(UUID().uuidString.lowercased())"
    )
    do {
      try FileManager.default.createSymbolicLink(
        atPath: temporary.path,
        withDestinationPath: manifest.releaseRootPath
      )
      _ = try FileManager.default.replaceItemAt(
        current,
        withItemAt: temporary,
        backupItemName: nil,
        options: []
      )
    } catch {
      try? FileManager.default.removeItem(at: temporary)
      throw MacOSHostPlatformReleaseServiceReconciliationError
        .activationFailed(String(describing: error))
    }
  }

  private func runLaunchctl(
    _ arguments: [String],
    action: String,
    service: String
  ) throws {
    let process = processFactory()
    process.executableURL = launchctlURL
    process.arguments = arguments
    try process.run()
    process.waitUntilExit()
    guard process.terminationReason == .exit,
      process.terminationStatus == 0
    else {
      throw MacOSHostPlatformReleaseServiceReconciliationError
        .serviceCommandFailed(
          action: action,
          service: service,
          status: process.terminationStatus
        )
    }
  }

  private func publish(
    source: URL,
    destinationPath: String
  ) throws {
    let destination = URL(fileURLWithPath: destinationPath)
    let temporary = destination.deletingLastPathComponent()
      .appendingPathComponent(
        ".\(destination.lastPathComponent).publishing-\(UUID().uuidString)"
      )
    do {
      try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try FileManager.default.copyItem(at: source, to: temporary)
      if FileManager.default.fileExists(atPath: destination.path) {
        _ = try FileManager.default.replaceItemAt(
          destination,
          withItemAt: temporary
        )
      } else {
        try FileManager.default.moveItem(at: temporary, to: destination)
      }
    } catch {
      try? FileManager.default.removeItem(at: temporary)
      throw MacOSHostPlatformReleaseServiceReconciliationError
        .publicationFailed(
          path: destinationPath,
          reason: String(describing: error)
        )
    }
  }

  private func candidateRoot(
    for release: HostPlatformRelease
  ) throws -> URL {
    let root =
      installationRoot
      .appendingPathComponent(release.slotRelativePath)
      .standardizedFileURL
    try requireContained(root)
    return root
  }

  private func candidateRoot(
    releaseId: String,
    releaseRootPath: String
  ) throws -> URL {
    let releaseRoot = URL(
      fileURLWithPath: releaseRootPath
    ).standardizedFileURL
    let root = releaseRoot.deletingLastPathComponent()
    try requireContained(root)
    return root
  }

  private func requireContained(_ url: URL) throws {
    let prefix =
      installationRoot.path.hasSuffix("/")
      ? installationRoot.path : installationRoot.path + "/"
    guard url.path.hasPrefix(prefix) else {
      throw MacOSHostPlatformReleaseServiceReconciliationError
        .manifestMismatch("release path escapes installation root")
    }
  }

  private func verify(_ url: URL, expected: String) throws {
    do {
      let values = try url.resourceValues(
        forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
      )
      guard values.isRegularFile == true,
        values.isSymbolicLink != true
      else {
        throw CocoaError(.fileReadUnsupportedScheme)
      }
      let handle = try FileHandle(forReadingFrom: url)
      defer { try? handle.close() }
      var digest = SHA256()
      while true {
        let data = try handle.read(upToCount: 1_048_576) ?? Data()
        if data.isEmpty {
          break
        }
        digest.update(data: data)
      }
      let actual = digest.finalize().map {
        String(format: "%02x", $0)
      }.joined()
      guard actual == expected else {
        throw MacOSHostPlatformReleaseServiceReconciliationError
          .immutableEntryInvalid(
            path: url.path,
            reason: "digest expected=\(expected) actual=\(actual)"
          )
      }
    } catch let error as MacOSHostPlatformReleaseServiceReconciliationError {
      throw error
    } catch {
      throw MacOSHostPlatformReleaseServiceReconciliationError
        .immutableEntryInvalid(
          path: url.path,
          reason: String(describing: error)
        )
    }
  }

  private func receipt(
    _ request: HostPlatformServiceReconciliationRequest,
    outcome: HostPlatformServiceReconciliationOutcome,
    reason: String?
  ) -> HostPlatformServiceReconciliationReceipt {
    HostPlatformServiceReconciliationReceipt(
      schemaVersion:
        HostPlatformInstallationContract.serviceReceiptSchemaVersion,
      reconciliationId: request.reconciliationId,
      operationId: request.operationId,
      installationId: request.installationId,
      expectedInstallationRevision: request.expectedInstallationRevision,
      targetReleaseId: request.targetRelease.id,
      targetReleaseSHA256: request.targetRelease.sha256,
      outcome: outcome,
      observedAt: observedAt(),
      failureReason: reason
    )
  }
}
