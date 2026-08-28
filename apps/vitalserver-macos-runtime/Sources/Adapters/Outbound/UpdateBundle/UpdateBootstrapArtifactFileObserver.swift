import Application
import Contracts
import CryptoKit
import Foundation

public struct UpdateBootstrapArtifactFileObserver {
    private let bundleDirectory: URL

    public init(bundleDirectory: URL) {
        self.bundleDirectory = bundleDirectory.standardizedFileURL
    }

    public func observe(
        _ artifact: UpdateBootstrapArtifact
    ) -> UpdateBootstrapArtifactObservation {
        let artifactURL = bundleDirectory
            .appendingPathComponent(artifact.relativePath)
            .standardizedFileURL
        let bundlePrefix = bundleDirectory.path.hasSuffix("/")
            ? bundleDirectory.path
            : bundleDirectory.path + "/"
        guard artifactURL.path.hasPrefix(bundlePrefix) else {
            return .failed(reason: "artifact path escapes the bundle directory")
        }

        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(
                atPath: artifactURL.path
            )
        } catch let error as CocoaError where error.code == .fileNoSuchFile {
            return .unavailable(reason: "artifact is missing")
        } catch {
            return .failed(reason: "artifact inspection failed: \(error)")
        }

        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            return .failed(reason: "artifact is not a regular file")
        }
        guard let size = attributes[.size] as? NSNumber else {
            return .failed(reason: "artifact size is unavailable")
        }

        do {
            let digest = try sha256(artifactURL)
            return .available(
                sha256: digest,
                sizeBytes: size.intValue
            )
        } catch {
            return .failed(reason: "artifact digest read failed: \(error)")
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
        return digest.finalize()
            .map { String(format: "%02x", $0) }
            .joined()
    }
}
