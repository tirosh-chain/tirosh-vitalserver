import Application
import Contracts
import CryptoKit
import Foundation

public enum ImmutableHostPlatformCandidateStagingError:
  Error,
  Equatable,
  Sendable
{
  case sourceUnavailable(path: String, reason: String)
  case sourceIsNotFile(path: String)
  case sourceDigestMismatch(expected: String, actual: String)
  case destinationAlreadyExists(path: String)
  case destinationInspectionFailed(path: String, reason: String)
  case stagedDigestMismatch(expected: String, actual: String)
  case stagingFailed(reason: String)
  case stagingAndCleanupFailed(staging: String, cleanup: String)
}

public struct ImmutableHostPlatformCandidateStager:
  HostPlatformCandidateStaging,
  Sendable
{
  public let installationRoot: URL
  private let observedAt: @Sendable () -> String

  public init(
    installationRoot: URL,
    observedAt: @escaping @Sendable () -> String = {
      ISO8601DateFormatter().string(from: Date())
    }
  ) {
    self.installationRoot = installationRoot
    self.observedAt = observedAt
  }

  public func stageCandidate(
    command: HostPlatformInstallationCommand
  ) -> HostPlatformCandidateStagingResult {
    do {
      let source = URL(fileURLWithPath: command.sourceArtifactPath)
      let destination = installationRoot.appendingPathComponent(
        command.targetRelease.slotRelativePath
      )
      let temporary =
        destination
        .deletingLastPathComponent()
        .appendingPathComponent(
          ".\(destination.lastPathComponent).staging-\(command.stagingAttemptId)"
        )
      try requireRegularFile(source)
      let sourceDigest = try sha256(source)
      guard sourceDigest == command.targetRelease.sha256 else {
        throw
          ImmutableHostPlatformCandidateStagingError
          .sourceDigestMismatch(
            expected: command.targetRelease.sha256,
            actual: sourceDigest
          )
      }
      try requireMissing(destination)
      try requireMissing(temporary)
      try FileManager.default.createDirectory(
        at: destination.deletingLastPathComponent(),
        withIntermediateDirectories: true
      )
      do {
        try FileManager.default.copyItem(at: source, to: temporary)
        let stagedDigest = try sha256(temporary)
        guard stagedDigest == command.targetRelease.sha256 else {
          throw
            ImmutableHostPlatformCandidateStagingError
            .stagedDigestMismatch(
              expected: command.targetRelease.sha256,
              actual: stagedDigest
            )
        }
        try FileManager.default.moveItem(at: temporary, to: destination)
      } catch {
        let staging = String(describing: error)
        if FileManager.default.fileExists(atPath: temporary.path) {
          do {
            try FileManager.default.removeItem(at: temporary)
          } catch {
            throw
              ImmutableHostPlatformCandidateStagingError
              .stagingAndCleanupFailed(
                staging: staging,
                cleanup: String(describing: error)
              )
          }
        }
        throw ImmutableHostPlatformCandidateStagingError.stagingFailed(
          reason: staging
        )
      }
      return .staged(
        HostPlatformStagedCandidate(
          release: command.targetRelease,
          stagingReceiptId:
            "\(command.operationId).candidate.\(command.targetRelease.sha256)",
          stagedAt: observedAt()
        )
      )
    } catch {
      return .failed(reason: String(describing: error))
    }
  }

  private func requireRegularFile(_ url: URL) throws {
    do {
      let values = try url.resourceValues(
        forKeys: [.isRegularFileKey]
      )
      guard values.isRegularFile == true else {
        throw
          ImmutableHostPlatformCandidateStagingError
          .sourceIsNotFile(path: url.path)
      }
    } catch let error as ImmutableHostPlatformCandidateStagingError {
      throw error
    } catch {
      throw
        ImmutableHostPlatformCandidateStagingError
        .sourceUnavailable(
          path: url.path,
          reason: String(describing: error)
        )
    }
  }

  private func requireMissing(_ url: URL) throws {
    do {
      _ = try url.resourceValues(forKeys: [.fileResourceTypeKey])
      throw
        ImmutableHostPlatformCandidateStagingError
        .destinationAlreadyExists(path: url.path)
    } catch let error as ImmutableHostPlatformCandidateStagingError {
      throw error
    } catch {
      let nsError = error as NSError
      if nsError.domain == NSCocoaErrorDomain,
        nsError.code == NSFileReadNoSuchFileError
      {
        return
      }
      throw
        ImmutableHostPlatformCandidateStagingError
        .destinationInspectionFailed(
          path: url.path,
          reason: String(describing: error)
        )
    }
  }

  private func sha256(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer {
      try? handle.close()
    }
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
}
