import Application
import Contracts
import CryptoKit
import Darwin
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
  case closureViolation(path: String, reason: String)
  case serviceCommandFailed(
    action: String,
    service: String,
    status: Int32,
    reason: String
  )
  case serviceStateReadFailed(service: String, reason: String)
  case serviceStopSettlementTimedOut(service: String, timeoutSeconds: Int)
  case serviceLoadedProofFailed(service: String, reason: String)
  case publicationFailed(path: String, reason: String)
  case activationFailed(String)
}

extension MacOSHostPlatformReleaseServiceReconciliationError:
  HostPlatformReconciliationFailure
{
  public var reconciliationReason: String {
    switch self {
    case .manifestReadFailed(let path, let reason):
      return "manifest read failed path=\(path) reason=\(reason)"
    case .manifestMismatch(let reason):
      return "manifest mismatch reason=\(reason)"
    case .activeReleaseMismatch(let expected, let actual):
      return "active release mismatch expected=\(expected) actual=\(actual)"
    case .immutableEntryInvalid(let path, let reason):
      return "immutable entry invalid path=\(path) reason=\(reason)"
    case .closureViolation(let path, let reason):
      return "closure violation path=\(path) reason=\(reason)"
    case .serviceCommandFailed(let action, let service, let status, let reason):
      return "service command failed action=\(action) service=\(service) status=\(status) reason=\(reason)"
    case .serviceStateReadFailed(let service, let reason):
      return "service state read failed service=\(service) reason=\(reason)"
    case .serviceStopSettlementTimedOut(let service, let timeoutSeconds):
      return "service stop settlement timed out service=\(service) timeoutSeconds=\(timeoutSeconds)"
    case .serviceLoadedProofFailed(let service, let reason):
      return "service loaded proof failed service=\(service) reason=\(reason)"
    case .publicationFailed(let path, let reason):
      return "publication failed path=\(path) reason=\(reason)"
    case .activationFailed(let reason):
      return "activation failed reason=\(reason)"
    }
  }
}

public struct MacOSHostPlatformReleaseServiceReconciler:
  HostPlatformReleaseReconciling,
  @unchecked Sendable
{
  public let installationRoot: URL
  public let launchctlURL: URL
  private let processFactory: () -> Process
  private let processCollector: RuntimeProcessOutputCollector
  private let now: () -> Date
  private let sleep: (TimeInterval) -> Void
  private let vmStopTimeoutSeconds: TimeInterval
  private let serviceStopTimeoutSeconds: TimeInterval
  private let serviceStopPollIntervalSeconds: TimeInterval

  public init(
    installationRoot: URL,
    launchctlURL: URL = URL(fileURLWithPath: "/bin/launchctl"),
    processFactory: @escaping () -> Process = Process.init,
    processCollector: RuntimeProcessOutputCollector =
      RuntimeProcessOutputCollector(),
    now: @escaping () -> Date = Date.init,
    sleep: @escaping (TimeInterval) -> Void = {
      Thread.sleep(forTimeInterval: $0)
    },
    vmStopTimeoutSeconds: TimeInterval = 900,
    serviceStopTimeoutSeconds: TimeInterval = 30,
    serviceStopPollIntervalSeconds: TimeInterval = 0.5
  ) {
    self.installationRoot = installationRoot.standardizedFileURL
    self.launchctlURL = launchctlURL
    self.processFactory = processFactory
    self.processCollector = processCollector
    self.now = now
    self.sleep = sleep
    self.vmStopTimeoutSeconds = vmStopTimeoutSeconds
    self.serviceStopTimeoutSeconds = serviceStopTimeoutSeconds
    self.serviceStopPollIntervalSeconds = serviceStopPollIntervalSeconds
  }

  public func loadReleaseManifest(
    _ release: HostPlatformRelease,
    installationId: String
  ) -> HostPlatformReleaseManifestLoadResult {
    do {
      return .loaded(
        try loadAndVerify(release, installationId: installationId)
      )
    } catch {
      return .failed(reason: String(describing: error))
    }
  }

  public func verifyTopology(
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
  }

  public func readCurrentReleaseTarget() -> HostPlatformCurrentReleaseTargetRead {
    let current = installationRoot.appendingPathComponent("current")
    let values: URLResourceValues
    do {
      values = try current.resourceValues(forKeys: [.isSymbolicLinkKey])
    } catch let error as NSError
      where error.domain == NSCocoaErrorDomain
      && error.code == NSFileReadNoSuchFileError {
      return .missing
    } catch {
      return .readFailed(String(describing: error))
    }
    guard values.isSymbolicLink == true else {
      return .notSymlink
    }
    do {
      let resolved = try URL(
        fileURLWithPath: FileManager.default.destinationOfSymbolicLink(
          atPath: current.path
        ),
        relativeTo: current.deletingLastPathComponent()
      ).standardizedFileURL
      return .resolved(resolved.path)
    } catch {
      return .readFailed(String(describing: error))
    }
  }

  public func readServiceStates(
    _ services: [HostPlatformRequiredService]
  ) -> [HostPlatformLaunchdServiceObservation] {
    services.map(readServiceState)
  }

  public func quiesceServices(
    _ services: [HostPlatformRequiredService]
  ) throws -> [HostPlatformLaunchdServiceObservation] {
    var observations: [HostPlatformLaunchdServiceObservation] = []
    for service in services.reversed() {
      let bootout = runLaunchctl(
        ["bootout", "system/\(service.name)"]
      )
      let outcome = RuntimeLaunchdServiceStateMapper.launchdOutcome(
        action: .bootout,
        exitCode: bootout.exitCode
      )
      switch outcome {
      case .accepted, .alreadyNotLoaded:
        observations.append(
          observation(
            service,
            action: .bootout,
            exitCode: bootout.exitCode,
            outcome: outcome
          )
        )
      case .permissionDenied, .failed, .loaded, .notLoaded:
        throw serviceCommandFailed(
          action: "bootout",
          service: service.name,
          outcome: bootout
        )
      }
      try waitUntilServiceStopped(
        service,
        observations: &observations
      )
    }
    return observations
  }

  public func publishInterfaces(
    _ manifest: HostPlatformReleaseArchiveManifest
  ) throws {
    try verifyCandidateClosure(manifest)
    try publishServiceDefinitions(manifest)
    try publishOperatorBootstrap(manifest)
    try publishOperatorApplication(manifest)
  }

  public func activateTarget(
    _ manifest: HostPlatformReleaseArchiveManifest
  ) throws -> String {
    let current = URL(fileURLWithPath: manifest.currentReleaseLinkPath)
    switch readCurrentReleaseTarget() {
    case .resolved(let path) where path == manifest.releaseRootPath:
      return path
    case .readFailed(let reason):
      throw MacOSHostPlatformReleaseServiceReconciliationError
        .activationFailed(reason)
    case .resolved, .notSymlink, .missing:
      break
    }
    let temporary = URL(
      fileURLWithPath:
        "\(current.path).activating-\(UUID().uuidString.lowercased())"
    )
    do {
      try FileManager.default.createSymbolicLink(
        atPath: temporary.path,
        withDestinationPath: manifest.releaseRootPath
      )
      let status = temporary.path.withCString { source in
        current.path.withCString { destination in
          Darwin.rename(source, destination)
        }
      }
      guard status == 0 else {
        throw NSError(
          domain: NSPOSIXErrorDomain,
          code: Int(errno),
          userInfo: [NSFilePathErrorKey: current.path]
        )
      }
    } catch {
      try? FileManager.default.removeItem(at: temporary)
      throw MacOSHostPlatformReleaseServiceReconciliationError
        .activationFailed(String(describing: error))
    }
    guard case .resolved(let path) = readCurrentReleaseTarget(),
      path == manifest.releaseRootPath
    else {
      throw MacOSHostPlatformReleaseServiceReconciliationError
        .activationFailed(
          "current release link does not resolve to target after activation"
        )
    }
    return manifest.releaseRootPath
  }

  public func loadServices(
    _ services: [HostPlatformRequiredService]
  ) throws -> [HostPlatformLaunchdServiceObservation] {
    var observations: [HostPlatformLaunchdServiceObservation] = []
    for service in services {
      let current = readServiceState(service)
      if current.outcome == .loaded {
        observations.append(current)
        continue
      }
      if current.outcome == .permissionDenied || current.outcome == .failed {
        throw MacOSHostPlatformReleaseServiceReconciliationError
          .serviceStateReadFailed(
            service: service.name,
            reason: current.outcome.rawValue
          )
      }
      let bootstrap = runLaunchctl(
        ["bootstrap", "system", service.definitionPath]
      )
      let outcome = RuntimeLaunchdServiceStateMapper.launchdOutcome(
        action: .bootstrap,
        exitCode: bootstrap.exitCode
      )
      guard outcome == .accepted else {
        throw serviceCommandFailed(
          action: "bootstrap",
          service: service.name,
          outcome: bootstrap
        )
      }
      observations.append(
        observation(
          service,
          action: .bootstrap,
          exitCode: bootstrap.exitCode,
          outcome: .accepted
        )
      )
      let proof = readServiceState(service)
      switch proof.outcome {
      case .loaded:
        observations.append(proof)
      case .notLoaded:
        throw MacOSHostPlatformReleaseServiceReconciliationError
          .serviceLoadedProofFailed(
            service: service.name,
            reason: "bootstrap accepted but service is not loaded"
          )
      case .permissionDenied, .failed:
        throw MacOSHostPlatformReleaseServiceReconciliationError
          .serviceStateReadFailed(
            service: service.name,
            reason: proof.outcome.rawValue
          )
      case .accepted, .alreadyNotLoaded:
        throw MacOSHostPlatformReleaseServiceReconciliationError
          .serviceStateReadFailed(
            service: service.name,
            reason: proof.outcome.rawValue
          )
      }
    }
    return observations
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

  private func verifyCandidateClosure(
    _ manifest: HostPlatformReleaseArchiveManifest
  ) throws {
    let candidateRoot = try candidateRoot(
      releaseId: manifest.release.id,
      releaseRootPath: manifest.releaseRootPath
    )
    var expected: Set<String> = [
      "release/installation-manifest.json",
      "operator-interface/runtime-console-bootstrap.json",
    ]
    for entry in manifest.files {
      expected.insert("release/\(entry.relativePath)")
    }
    for service in manifest.replaceableServices {
      expected.insert("service-definitions/\(service.role).plist")
    }
    let actual = try regularFiles(candidateRoot)
    let missing = expected.subtracting(actual)
    guard missing.isEmpty else {
      throw MacOSHostPlatformReleaseServiceReconciliationError
        .closureViolation(
          path: candidateRoot.path,
          reason: "missing declared files \(missing.sorted())"
        )
    }
    let extra = actual.subtracting(expected)
    guard extra.isEmpty else {
      throw MacOSHostPlatformReleaseServiceReconciliationError
        .closureViolation(
          path: candidateRoot.path,
          reason: "undeclared files \(extra.sorted())"
        )
    }
  }

  private func readServiceState(
    _ service: HostPlatformRequiredService
  ) -> HostPlatformLaunchdServiceObservation {
    let result = runLaunchctl(["print", "system/\(service.name)"])
    let outcome = RuntimeLaunchdServiceStateMapper.launchdOutcome(
      action: .print,
      exitCode: result.exitCode
    )
    return observation(
      service,
      action: .print,
      exitCode: result.exitCode,
      outcome: outcome
    )
  }

  private func observation(
    _ service: HostPlatformRequiredService,
    action: HostPlatformLaunchdAction,
    exitCode: Int32,
    outcome: HostPlatformLaunchdOutcome
  ) -> HostPlatformLaunchdServiceObservation {
    HostPlatformLaunchdServiceObservation(
      role: service.role,
      serviceName: service.name,
      action: action,
      exitCode: exitCode,
      outcome: outcome
    )
  }

  private func waitUntilServiceStopped(
    _ service: HostPlatformRequiredService,
    observations: inout [HostPlatformLaunchdServiceObservation]
  ) throws {
    let timeout =
      service.role == "vm"
      ? vmStopTimeoutSeconds : serviceStopTimeoutSeconds
    let deadline = now().addingTimeInterval(timeout)
    while true {
      let observation = readServiceState(service)
      switch observation.outcome {
      case .notLoaded:
        observations.append(observation)
        return
      case .loaded:
        guard now() < deadline else {
          throw MacOSHostPlatformReleaseServiceReconciliationError
            .serviceStopSettlementTimedOut(
              service: service.name,
              timeoutSeconds: Int(timeout)
            )
        }
        sleep(serviceStopPollIntervalSeconds)
      case .permissionDenied, .failed:
        throw MacOSHostPlatformReleaseServiceReconciliationError
          .serviceStateReadFailed(
            service: service.name,
            reason: observation.outcome.rawValue
          )
      case .accepted, .alreadyNotLoaded:
        throw MacOSHostPlatformReleaseServiceReconciliationError
          .serviceStateReadFailed(
            service: service.name,
            reason: observation.outcome.rawValue
          )
      }
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

  private func publishOperatorApplication(
    _ manifest: HostPlatformReleaseArchiveManifest
  ) throws {
    let releaseRoot = URL(
      fileURLWithPath: manifest.releaseRootPath,
      isDirectory: true
    )
    let source = releaseRoot.appendingPathComponent(
      manifest.operatorInterface.applicationBundleRelativePath,
      isDirectory: true
    )
    try publish(
      source: source,
      destinationPath: manifest.operatorInterface.applicationBundlePath
    )
    try provePublishedApplication(manifest)
  }

  private func provePublishedApplication(
    _ manifest: HostPlatformReleaseArchiveManifest
  ) throws {
    let application = URL(
      fileURLWithPath: manifest.operatorInterface.applicationBundlePath,
      isDirectory: true
    )
    do {
      let values = try application.resourceValues(
        forKeys: [.isDirectoryKey, .isSymbolicLinkKey]
      )
      guard values.isDirectory == true, values.isSymbolicLink != true else {
        throw MacOSHostPlatformReleaseServiceReconciliationError
          .publicationFailed(
            path: application.path,
            reason: "published operator application is not a materialized bundle"
          )
      }
      let prefix =
        manifest.operatorInterface.applicationBundleRelativePath + "/"
      let applicationEntries = manifest.files.filter {
        $0.relativePath.hasPrefix(prefix)
      }
      guard !applicationEntries.isEmpty else {
        throw MacOSHostPlatformReleaseServiceReconciliationError
          .manifestMismatch("operator application has no immutable entries")
      }
      var expectedRelative: Set<String> = []
      for entry in applicationEntries {
        let relativePath = String(entry.relativePath.dropFirst(prefix.count))
        expectedRelative.insert(relativePath)
        try verify(
          application.appendingPathComponent(relativePath),
          expected: entry.sha256
        )
      }
      let actual = try regularFiles(application)
      guard actual == expectedRelative else {
        let extra = actual.subtracting(expectedRelative)
        let missing = expectedRelative.subtracting(actual)
        throw MacOSHostPlatformReleaseServiceReconciliationError
          .closureViolation(
            path: application.path,
            reason:
              "published application closure differs extra=\(extra.sorted()) missing=\(missing.sorted())"
          )
      }
      let entrypoint = application.appendingPathComponent(
        manifest.operatorInterface.applicationBundleEntrypointRelativePath
      )
      guard FileManager.default.isExecutableFile(atPath: entrypoint.path) else {
        throw MacOSHostPlatformReleaseServiceReconciliationError
          .publicationFailed(
            path: entrypoint.path,
            reason: "published operator application entrypoint is not executable"
          )
      }
    } catch let error as MacOSHostPlatformReleaseServiceReconciliationError {
      throw error
    } catch {
      throw MacOSHostPlatformReleaseServiceReconciliationError
        .publicationFailed(
          path: application.path,
          reason: String(describing: error)
        )
    }
  }

  private func runLaunchctl(
    _ arguments: [String]
  ) -> RuntimeProcessOutcome {
    processCollector.run(
      executableURL: launchctlURL,
      arguments: arguments,
      processFactory: processFactory
    )
  }

  private func serviceCommandFailed(
    action: String,
    service: String,
    outcome: RuntimeProcessOutcome
  ) -> MacOSHostPlatformReleaseServiceReconciliationError {
    let reason = commandFailureReason(outcome)
    return .serviceCommandFailed(
      action: action,
      service: service,
      status: outcome.exitCode,
      reason: reason
    )
  }

  private func commandFailureReason(_ outcome: RuntimeProcessOutcome) -> String {
    let stderr = outcome.stderr.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    if !stderr.isEmpty {
      return stderr
    }
    let stdout = outcome.stdout.trimmingCharacters(
      in: .whitespacesAndNewlines
    )
    if !stdout.isEmpty {
      return stdout
    }
    return "launchctl produced no diagnostic output"
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
    let displacedSymbolicLink = destination.deletingLastPathComponent()
      .appendingPathComponent(
        ".\(destination.lastPathComponent).displaced-\(UUID().uuidString)"
      )
    do {
      try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      try FileManager.default.copyItem(at: source, to: temporary)
      let destinationType =
        try? FileManager.default.attributesOfItem(
          atPath: destination.path
        )[.type] as? FileAttributeType
      if destinationType == .typeSymbolicLink {
        try FileManager.default.moveItem(
          at: destination,
          to: displacedSymbolicLink
        )
        do {
          try FileManager.default.moveItem(at: temporary, to: destination)
          try FileManager.default.removeItem(at: displacedSymbolicLink)
        } catch {
          if !FileManager.default.fileExists(atPath: destination.path) {
            try? FileManager.default.moveItem(
              at: displacedSymbolicLink,
              to: destination
            )
          }
          throw error
        }
      } else if destinationType != nil {
        _ = try FileManager.default.replaceItemAt(
          destination,
          withItemAt: temporary
        )
      } else {
        try FileManager.default.moveItem(at: temporary, to: destination)
      }
    } catch {
      try? FileManager.default.removeItem(at: temporary)
      try? FileManager.default.removeItem(at: displacedSymbolicLink)
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

  private func regularFiles(_ root: URL) throws -> Set<String> {
    let resolvedRoot = root.resolvingSymlinksInPath().standardizedFileURL
    guard let enumerator = FileManager.default.enumerator(
      at: root,
      includingPropertiesForKeys: [
        .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
      ],
      options: []
    ) else {
      throw MacOSHostPlatformReleaseServiceReconciliationError
        .closureViolation(
          path: root.path,
          reason: "cannot enumerate directory"
        )
    }
    var files: Set<String> = []
    for case let url as URL in enumerator {
      let resolvedURL = url.resolvingSymlinksInPath().standardizedFileURL
      let values = try url.resourceValues(
        forKeys: [
          .isDirectoryKey, .isRegularFileKey, .isSymbolicLinkKey,
        ]
      )
      guard values.isSymbolicLink != true,
        values.isDirectory == true || values.isRegularFile == true
      else {
        throw MacOSHostPlatformReleaseServiceReconciliationError
          .closureViolation(
            path: url.path,
            reason: "unexpected symlink or special file"
          )
      }
      if values.isRegularFile == true {
        let prefix =
          resolvedRoot.path.hasSuffix("/")
          ? resolvedRoot.path : resolvedRoot.path + "/"
        guard resolvedURL.path.hasPrefix(prefix) else {
          throw MacOSHostPlatformReleaseServiceReconciliationError
            .closureViolation(
              path: url.path,
              reason: "path escapes enumerated root"
            )
        }
        files.insert(String(resolvedURL.path.dropFirst(prefix.count)))
      }
    }
    return files
  }
}
