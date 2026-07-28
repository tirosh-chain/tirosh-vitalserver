import Application
import Contracts
import CryptoKit
import Foundation

public enum HostPlatformReleaseArchiveCandidateStagingError:
  Error,
  Equatable,
  Sendable
{
  case sourceInvalid(String)
  case archiveListingFailed(String)
  case unsafeArchiveEntry(String)
  case duplicateArchiveEntry(String)
  case archiveExtractionFailed(String)
  case manifestInvalid(String)
  case unexpectedArchiveEntry(String)
  case missingArchiveEntry(String)
  case entryDigestMismatch(path: String, expected: String, actual: String)
  case destinationAlreadyExists(String)
  case persistenceFailed(String)
}

public struct HostPlatformReleaseArchiveCandidateStager:
  HostPlatformCandidateStaging,
  @unchecked Sendable
{
  public static let maximumArchiveBytes: UInt64 = 8 * 1024 * 1024 * 1024

  public let installationRoot: URL
  private let observedAt: @Sendable () -> String
  private let processFactory: () -> Process

  public init(
    installationRoot: URL,
    observedAt: @escaping @Sendable () -> String = {
      ISO8601DateFormatter().string(from: Date())
    },
    processFactory: @escaping () -> Process = Process.init
  ) {
    self.installationRoot = installationRoot.standardizedFileURL
    self.observedAt = observedAt
    self.processFactory = processFactory
  }

  public func stageCandidate(
    command: HostPlatformInstallationCommand
  ) -> HostPlatformCandidateStagingResult {
    let fileManager = FileManager.default
    let source = URL(fileURLWithPath: command.sourceArtifactPath)
    let destination =
      installationRoot
      .appendingPathComponent(command.targetRelease.slotRelativePath)
      .standardizedFileURL
    let temporary =
      installationRoot
      .appendingPathComponent(
        ".candidate-\(command.stagingAttemptId)",
        isDirectory: true
      )
    do {
      try validateSource(
        source,
        expectedSHA256: command.targetRelease.sha256,
        expectedSizeBytes: command.sourceArtifactSizeBytes,
        mediaType: command.sourceArtifactMediaType
      )
      try requireContained(destination)
      try requireMissing(destination)
      try requireMissing(temporary)
      let entries = try listArchive(source)
      try validateArchiveEntryNames(entries)
      try fileManager.createDirectory(
        at: installationRoot,
        withIntermediateDirectories: true
      )
      try fileManager.createDirectory(
        at: temporary,
        withIntermediateDirectories: false
      )
      do {
        try extractArchive(source, to: temporary)
        let manifest = try validateExtractedArchive(
          at: temporary,
          command: command,
          destination: destination
        )
        guard manifest.release.id == command.targetRelease.id,
          manifest.release.version == command.targetRelease.version
        else {
          throw HostPlatformReleaseArchiveCandidateStagingError
            .manifestInvalid("release identity does not match command")
        }
        try fileManager.createDirectory(
          at: destination.deletingLastPathComponent(),
          withIntermediateDirectories: true
        )
        try fileManager.moveItem(at: temporary, to: destination)
      } catch {
        try? fileManager.removeItem(at: temporary)
        throw error
      }
      return .staged(
        HostPlatformStagedCandidate(
          release: command.targetRelease,
          stagingReceiptId:
            "\(command.operationId).archive.\(command.targetRelease.sha256)",
          stagedAt: observedAt()
        )
      )
    } catch {
      return .failed(reason: String(describing: error))
    }
  }

  private func validateSource(
    _ source: URL,
    expectedSHA256: String,
    expectedSizeBytes: UInt64,
    mediaType: String
  ) throws {
    let values = try source.resourceValues(
      forKeys: [
        .isRegularFileKey,
        .isSymbolicLinkKey,
        .fileSizeKey,
      ]
    )
    guard values.isRegularFile == true,
      values.isSymbolicLink != true,
      let fileSize = values.fileSize,
      fileSize > 0,
      UInt64(fileSize) == expectedSizeBytes,
      UInt64(fileSize) <= Self.maximumArchiveBytes
    else {
      throw HostPlatformReleaseArchiveCandidateStagingError
        .sourceInvalid(source.path)
    }
    guard mediaType == HostPlatformReleaseArchiveContract.mediaType
    else {
      throw HostPlatformReleaseArchiveCandidateStagingError
        .sourceInvalid("unsupported media type")
    }
    let actual = try sha256(source)
    guard actual == expectedSHA256 else {
      throw HostPlatformReleaseArchiveCandidateStagingError
        .entryDigestMismatch(
          path: source.path,
          expected: expectedSHA256,
          actual: actual
        )
    }
  }

  private func listArchive(_ source: URL) throws -> [String] {
    let process = processFactory()
    let output = Pipe()
    let errors = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
    process.environment =
      ProcessInfo.processInfo.environment.merging(
        ["COPYFILE_DISABLE": "1"]
      ) { _, explicit in explicit }
    process.arguments = ["-tzf", source.path]
    process.standardOutput = output
    process.standardError = errors
    try process.run()
    process.waitUntilExit()
    guard process.terminationReason == .exit,
      process.terminationStatus == 0
    else {
      let reason = String(
        data: errors.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
      ) ?? "tar listing failed without stderr"
      throw HostPlatformReleaseArchiveCandidateStagingError
        .archiveListingFailed(reason)
    }
    let text = String(
      data: output.fileHandleForReading.readDataToEndOfFile(),
      encoding: .utf8
    ) ?? ""
    return text.split(separator: "\n", omittingEmptySubsequences: true).map(
      String.init
    )
  }

  private func validateArchiveEntryNames(_ entries: [String]) throws {
    var seen: Set<String> = []
    for entry in entries {
      let normalized =
        entry.hasSuffix("/") ? String(entry.dropLast()) : entry
      let components = normalized.split(separator: "/", omittingEmptySubsequences: false)
      guard !normalized.isEmpty,
        !normalized.hasPrefix("/"),
        !normalized.contains("\\"),
        !components.contains(""),
        !components.contains("."),
        !components.contains("..")
      else {
        throw HostPlatformReleaseArchiveCandidateStagingError
          .unsafeArchiveEntry(entry)
      }
      guard seen.insert(normalized).inserted else {
        throw HostPlatformReleaseArchiveCandidateStagingError
          .duplicateArchiveEntry(normalized)
      }
    }
  }

  private func extractArchive(_ source: URL, to destination: URL) throws {
    let process = processFactory()
    let errors = Pipe()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
    process.environment =
      ProcessInfo.processInfo.environment.merging(
        ["COPYFILE_DISABLE": "1"]
      ) { _, explicit in explicit }
    process.arguments = [
      "-xzf", source.path,
      "-C", destination.path,
      "--no-same-owner",
      "--no-same-permissions",
    ]
    process.standardError = errors
    try process.run()
    process.waitUntilExit()
    guard process.terminationReason == .exit,
      process.terminationStatus == 0
    else {
      let reason = String(
        data: errors.fileHandleForReading.readDataToEndOfFile(),
        encoding: .utf8
      ) ?? "tar extraction failed without stderr"
      throw HostPlatformReleaseArchiveCandidateStagingError
        .archiveExtractionFailed(reason)
    }
  }

  private func validateExtractedArchive(
    at root: URL,
    command: HostPlatformInstallationCommand,
    destination: URL
  ) throws -> HostPlatformReleaseArchiveManifest {
    let manifestURL = root.appendingPathComponent(
      "release/installation-manifest.json"
    )
    let data = try Data(contentsOf: manifestURL)
    guard data.count <= 1_048_576 else {
      throw HostPlatformReleaseArchiveCandidateStagingError
        .manifestInvalid("manifest exceeds 1 MiB")
    }
    try validateManifestDocument(data)
    let manifest = try JSONDecoder().decode(
      HostPlatformReleaseArchiveManifest.self,
      from: data
    )
    let declaredReleaseRoot = destination.appendingPathComponent(
      "release",
      isDirectory: true
    ).standardizedFileURL
    let extractedReleaseRoot = root.appendingPathComponent(
      "release",
      isDirectory: true
    )
    let current = installationRoot.appendingPathComponent("current")
    guard manifest.schemaVersion
        == HostPlatformReleaseArchiveContract.manifestSchemaVersion,
      manifest.installationId == command.installationId,
      manifest.releaseCatalogPath == installationRoot.path,
      manifest.releaseRootPath == declaredReleaseRoot.path,
      manifest.currentReleaseLinkPath == current.path,
      !manifest.replaceableServices.isEmpty,
      stableBoundaryIsExplicit(manifest)
    else {
      throw HostPlatformReleaseArchiveCandidateStagingError
        .manifestInvalid("host installation layout does not match manager root")
    }

    var expected: [String: String?] = [
      "release/installation-manifest.json": nil,
      "operator-interface/runtime-console-bootstrap.json":
        manifest.operatorInterface.bootstrapConfigurationSha256,
    ]
    for entry in manifest.files {
      try requireSafeRelativePath(entry.relativePath)
      expected["release/\(entry.relativePath)"] = entry.sha256
    }
    try requireSafeRelativePath(
      manifest.operatorInterface.applicationBundleRelativePath
    )
    try requireSafeRelativePath(
      manifest.operatorInterface.applicationBundleEntrypointRelativePath
    )
    let applicationBundle = extractedReleaseRoot.appendingPathComponent(
      manifest.operatorInterface.applicationBundleRelativePath,
      isDirectory: true
    )
    let applicationEntrypoint = applicationBundle.appendingPathComponent(
      manifest.operatorInterface.applicationBundleEntrypointRelativePath
    )
    guard manifest.operatorInterface.applicationBundlePath.hasPrefix("/"),
      FileManager.default.isExecutableFile(atPath: applicationEntrypoint.path)
    else {
      throw HostPlatformReleaseArchiveCandidateStagingError
        .manifestInvalid(
          "application bundle path or executable entrypoint is invalid"
        )
    }
    let applicationPrefix =
      manifest.operatorInterface.applicationBundleRelativePath + "/"
    let applicationFiles = manifest.files.filter {
      $0.relativePath.hasPrefix(applicationPrefix)
    }
    guard !applicationFiles.isEmpty else {
      throw HostPlatformReleaseArchiveCandidateStagingError
        .manifestInvalid("application bundle has no declared files")
    }
    let applicationTreeDigest = declaredTreeSHA256(
      applicationFiles,
      removingPrefix: applicationPrefix
    )
    guard applicationTreeDigest
      == manifest.operatorInterface.applicationBundleTreeSha256
    else {
      throw HostPlatformReleaseArchiveCandidateStagingError
        .entryDigestMismatch(
          path: manifest.operatorInterface.applicationBundleRelativePath,
          expected:
            manifest.operatorInterface.applicationBundleTreeSha256,
          actual: applicationTreeDigest
        )
    }
    for service in manifest.replaceableServices {
      guard service.manager == "launchd", !service.role.isEmpty else {
        throw HostPlatformReleaseArchiveCandidateStagingError
          .manifestInvalid("macOS service declaration is invalid")
      }
      expected["service-definitions/\(service.role).plist"] =
        service.definitionSha256
    }

    let actual = try regularFiles(root)
    for path in actual where !expected.keys.contains(path) {
      throw HostPlatformReleaseArchiveCandidateStagingError
        .unexpectedArchiveEntry(path)
    }
    for (path, digest) in expected {
      guard actual.contains(path) else {
        throw HostPlatformReleaseArchiveCandidateStagingError
          .missingArchiveEntry(path)
      }
      if let digest {
        let fileURL = root.appendingPathComponent(path)
        let actualDigest = try sha256(fileURL)
        guard actualDigest == digest else {
          throw HostPlatformReleaseArchiveCandidateStagingError
            .entryDigestMismatch(
              path: path,
              expected: digest,
              actual: actualDigest
            )
        }
        if path.hasPrefix("release/"),
          let declaration = manifest.files.first(where: {
            "release/\($0.relativePath)" == path
          }),
          declaration.executable,
          !FileManager.default.isExecutableFile(atPath: fileURL.path)
        {
          throw HostPlatformReleaseArchiveCandidateStagingError
            .manifestInvalid("declared executable is not executable: \(path)")
        }
      }
    }
    return manifest
  }

  private func validateManifestDocument(_ data: Data) throws {
    guard
      let root = try JSONSerialization.jsonObject(with: data)
        as? [String: Any]
    else {
      throw HostPlatformReleaseArchiveCandidateStagingError
        .manifestInvalid("manifest root must be an object")
    }
    try requireKeys(
      root,
      [
        "schemaVersion", "installationId", "release",
        "releaseCatalogPath", "releaseRootPath", "currentReleaseLinkPath",
        "files", "operatorInterface", "replaceableServices",
        "stableComponents", "mutableStores",
      ],
      "manifest"
    )
    try requireObjectKeys(root["release"], ["id", "version"], "release")
    try requireObjectKeys(
      root["operatorInterface"],
      [
        "bootstrapConfigurationPath", "bootstrapConfigurationSha256",
        "applicationBundlePath", "applicationBundleRelativePath",
        "applicationBundleTreeSha256",
        "applicationBundleEntrypointRelativePath",
      ],
      "operatorInterface"
    )
    try requireArrayObjectKeys(
      root["files"],
      ["relativePath", "sha256", "executable"],
      "files"
    )
    try requireArrayObjectKeys(
      root["replaceableServices"],
      ["role", "manager", "name", "definitionPath", "definitionSha256"],
      "replaceableServices"
    )
    guard let stableComponents = root["stableComponents"] as? [Any] else {
      throw HostPlatformReleaseArchiveCandidateStagingError
        .manifestInvalid("stableComponents must be an array")
    }
    for (index, item) in stableComponents.enumerated() {
      guard let object = item as? [String: Any] else {
        throw HostPlatformReleaseArchiveCandidateStagingError
          .manifestInvalid("stableComponents[\(index)] must be an object")
      }
      let keys = Set(object.keys)
      guard keys == ["role", "executablePath"]
        || keys == ["role", "executablePath", "serviceName"]
      else {
        throw HostPlatformReleaseArchiveCandidateStagingError
          .manifestInvalid(
            "stableComponents[\(index)] fields differ from contract"
          )
      }
    }
    try requireArrayObjectKeys(
      root["mutableStores"],
      ["id", "path", "kind", "owner", "retention"],
      "mutableStores"
    )
  }

  private func requireObjectKeys(
    _ value: Any?,
    _ keys: Set<String>,
    _ location: String
  ) throws {
    guard let object = value as? [String: Any] else {
      throw HostPlatformReleaseArchiveCandidateStagingError
        .manifestInvalid("\(location) must be an object")
    }
    try requireKeys(object, keys, location)
  }

  private func requireArrayObjectKeys(
    _ value: Any?,
    _ keys: Set<String>,
    _ location: String
  ) throws {
    guard let array = value as? [Any] else {
      throw HostPlatformReleaseArchiveCandidateStagingError
        .manifestInvalid("\(location) must be an array")
    }
    for (index, item) in array.enumerated() {
      try requireObjectKeys(item, keys, "\(location)[\(index)]")
    }
  }

  private func requireKeys(
    _ object: [String: Any],
    _ keys: Set<String>,
    _ location: String
  ) throws {
    let actual = Set(object.keys)
    guard actual == keys else {
      throw HostPlatformReleaseArchiveCandidateStagingError
        .manifestInvalid(
          "\(location) fields differ missing=\(keys.subtracting(actual).sorted()) unknown=\(actual.subtracting(keys).sorted())"
        )
    }
  }

  private func stableBoundaryIsExplicit(
    _ manifest: HostPlatformReleaseArchiveManifest
  ) -> Bool {
    let stableRoles = Set(manifest.stableComponents.map(\.role))
    let replaceableRoles = Set(manifest.replaceableServices.map(\.role))
    guard stableRoles
      == Set([
        "host-installation-manager",
        "update-handoff-supervisor",
      ]), stableRoles.isDisjoint(with: replaceableRoles)
    else {
      return false
    }
    for component in manifest.stableComponents {
      guard component.executablePath.hasPrefix("/"),
        !manifest.files.contains(where: {
          URL(fileURLWithPath: component.executablePath).lastPathComponent
            == URL(fileURLWithPath: $0.relativePath).lastPathComponent
        })
      else {
        return false
      }
    }
    guard manifest.stableComponents.first(where: {
      $0.role == "host-installation-manager"
    })?.serviceName == nil,
      !(manifest.stableComponents.first(where: {
        $0.role == "update-handoff-supervisor"
      })?.serviceName ?? "").isEmpty
    else {
      return false
    }
    return true
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
      throw HostPlatformReleaseArchiveCandidateStagingError
        .archiveExtractionFailed("cannot enumerate extracted archive")
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
        throw HostPlatformReleaseArchiveCandidateStagingError
          .unsafeArchiveEntry(url.path)
      }
      if values.isRegularFile == true {
        let prefix =
          resolvedRoot.path.hasSuffix("/")
          ? resolvedRoot.path : resolvedRoot.path + "/"
        guard resolvedURL.path.hasPrefix(prefix) else {
          throw HostPlatformReleaseArchiveCandidateStagingError
            .unsafeArchiveEntry(url.path)
        }
        files.insert(String(resolvedURL.path.dropFirst(prefix.count)))
      }
    }
    return files
  }

  private func requireSafeRelativePath(_ path: String) throws {
    let components = path.split(separator: "/", omittingEmptySubsequences: false)
    guard !path.isEmpty,
      !path.hasPrefix("/"),
      !path.contains("\\"),
      !components.contains(""),
      !components.contains("."),
      !components.contains("..")
    else {
      throw HostPlatformReleaseArchiveCandidateStagingError
        .manifestInvalid("unsafe relative path \(path)")
    }
  }

  private func requireContained(_ url: URL) throws {
    let prefix =
      installationRoot.path.hasSuffix("/")
      ? installationRoot.path : installationRoot.path + "/"
    guard url.path.hasPrefix(prefix) else {
      throw HostPlatformReleaseArchiveCandidateStagingError
        .persistenceFailed("destination escapes installation root")
    }
  }

  private func requireMissing(_ url: URL) throws {
    guard !FileManager.default.fileExists(atPath: url.path) else {
      throw HostPlatformReleaseArchiveCandidateStagingError
        .destinationAlreadyExists(url.path)
    }
  }

  private func sha256(_ url: URL) throws -> String {
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
    return digest.finalize().map {
      String(format: "%02x", $0)
    }.joined()
  }

  private func declaredTreeSHA256(
    _ files: [HostPlatformImmutablePayloadEntry],
    removingPrefix prefix: String
  ) -> String {
    var digest = SHA256()
    for file in files.sorted(by: { $0.relativePath < $1.relativePath }) {
      let relative = String(file.relativePath.dropFirst(prefix.count))
      digest.update(data: Data("regular-file\0".utf8))
      digest.update(data: Data(relative.utf8))
      digest.update(data: Data([0]))
      digest.update(data: Data(file.sha256.lowercased().utf8))
      digest.update(data: Data([0]))
    }
    return digest.finalize().map {
      String(format: "%02x", $0)
    }.joined()
  }
}
