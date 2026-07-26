import CryptoKit
import Foundation

// GuestRuntimeDiskProvisioner is the macOS Host filesystem adapter that turns
// one immutable C34 guest-root artifact into the separately owned writable
// runtime disk named by C32. It owns no Guest lifecycle policy and never
// treats a pre-existing disk as safe without the matching provisioning receipt.
public enum GuestRuntimeDiskProvisioningOutcome: String, Equatable, Sendable {
    case provisioned
    case retainedExistingRuntimeDisk = "retained-existing-runtime-disk"
}

public enum GuestRuntimeDiskProvisioningError: LocalizedError {
    case unavailable(String)
    case failed(String)

    public var errorDescription: String? {
        switch self {
        case .unavailable(let message), .failed(let message):
            message
        }
    }
}

public enum GuestRuntimeDiskProvisioner {
    public static func provision(
        configuration: GuestRuntimeDiskProvisioning
    ) throws -> GuestRuntimeDiskProvisioningOutcome {
        if let validationMessage = configuration.validationMessage {
            throw GuestRuntimeDiskProvisioningError.failed(
                "Guest Runtime disk provisioning configuration is invalid: \(validationMessage)"
            )
        }
        let releaseArtifact = try readDeclaredReleaseArtifact(configuration)
        let runtimeDiskURL = URL(fileURLWithPath: configuration.runtimeDiskImagePath)
        let receiptURL = URL(fileURLWithPath: configuration.provisioningReceiptPath)
        let fileManager = FileManager.default
        let runtimeDiskExists = fileManager.fileExists(atPath: runtimeDiskURL.path)
        let receiptExists = fileManager.fileExists(atPath: receiptURL.path)
        if runtimeDiskExists || receiptExists {
            guard runtimeDiskExists, receiptExists else {
                throw GuestRuntimeDiskProvisioningError.failed(
                    "Guest Runtime disk workspace and provisioning receipt must either both exist or both be absent"
                )
            }
            try requireRegularFile(runtimeDiskURL, resourceName: "Guest Runtime disk workspace")
            let receipt = try readProvisioningReceipt(receiptURL)
            guard receipt.matches(configuration: configuration, releaseArtifact: releaseArtifact) else {
                throw GuestRuntimeDiskProvisioningError.failed(
                    "existing Guest Runtime disk receipt does not match the configured immutable release artifact"
                )
            }
            return .retainedExistingRuntimeDisk
        }

        let workspaceDirectory = runtimeDiskURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: workspaceDirectory, withIntermediateDirectories: true)
        } catch {
            throw GuestRuntimeDiskProvisioningError.unavailable(
                "Guest Runtime disk workspace directory cannot be created: \(error.localizedDescription)"
            )
        }
        let receiptDirectory = receiptURL.deletingLastPathComponent()
        do {
            try fileManager.createDirectory(at: receiptDirectory, withIntermediateDirectories: true)
        } catch {
            throw GuestRuntimeDiskProvisioningError.unavailable(
                "Guest Runtime disk provisioning receipt directory cannot be created: \(error.localizedDescription)"
            )
        }

        let temporaryDiskURL = workspaceDirectory.appendingPathComponent(
            ".\(runtimeDiskURL.lastPathComponent).provisioning-\(UUID().uuidString)"
        )
        let temporaryReceiptURL = receiptDirectory.appendingPathComponent(
            ".\(receiptURL.lastPathComponent).provisioning-\(UUID().uuidString)"
        )
        defer {
            try? fileManager.removeItem(at: temporaryDiskURL)
            try? fileManager.removeItem(at: temporaryReceiptURL)
        }
        do {
            try fileManager.copyItem(at: URL(fileURLWithPath: configuration.releaseArtifactPath), to: temporaryDiskURL)
            try requireArtifactIdentity(temporaryDiskURL, artifact: releaseArtifact, resourceName: "provisioned Guest Runtime disk")
            let receipt = GuestRuntimeDiskProvisioningReceipt(
                schemaVersion: "v1",
                releaseArtifactManifestPath: configuration.releaseArtifactManifestPath,
                releaseArtifactPath: configuration.releaseArtifactPath,
                releaseArtifactSizeBytes: releaseArtifact.sizeBytes,
                releaseArtifactSHA256: releaseArtifact.sha256,
                runtimeDiskImagePath: configuration.runtimeDiskImagePath
            )
            try JSONEncoder.vitalserverSorted.encode(receipt).write(to: temporaryReceiptURL)
            guard !fileManager.fileExists(atPath: runtimeDiskURL.path), !fileManager.fileExists(atPath: receiptURL.path) else {
                throw GuestRuntimeDiskProvisioningError.failed(
                    "Guest Runtime disk workspace changed while provisioning was in progress"
                )
            }
            try fileManager.moveItem(at: temporaryDiskURL, to: runtimeDiskURL)
            try fileManager.moveItem(at: temporaryReceiptURL, to: receiptURL)
        } catch let error as GuestRuntimeDiskProvisioningError {
            throw error
        } catch {
            throw GuestRuntimeDiskProvisioningError.failed(
                "Guest Runtime disk provisioning could not publish a complete workspace: \(error.localizedDescription)"
            )
        }
        return .provisioned
    }

    private static func readDeclaredReleaseArtifact(
        _ configuration: GuestRuntimeDiskProvisioning
    ) throws -> GuestRootStorageReleaseArtifact {
        let manifestURL = URL(fileURLWithPath: configuration.releaseArtifactManifestPath)
        try requireRegularFile(manifestURL, resourceName: "Guest release artifact manifest")
        let manifest: GuestReleaseArtifactManifest
        do {
            manifest = try JSONDecoder().decode(GuestReleaseArtifactManifest.self, from: Data(contentsOf: manifestURL))
        } catch {
            throw GuestRuntimeDiskProvisioningError.unavailable(
                "Guest release artifact manifest cannot be decoded"
            )
        }
        guard manifest.schemaVersion == "v1",
              manifest.architecture == "arm64",
              !manifest.artifactSetId.isEmpty,
              let rootArtifact = manifest.storageDevices.first(where: {
                  $0.id == "guest-root" && $0.role == "guest-root-storage" && $0.storageImageFormat == "raw" && $0.guestVolumeFileSystem == nil
              }),
              manifest.storageDevices.filter({ $0.id == "guest-root" }).count == 1,
              rootArtifact.sizeBytes > 0,
              isSHA256(rootArtifact.sha256)
        else {
            throw GuestRuntimeDiskProvisioningError.failed(
                "Guest release artifact manifest does not declare one valid guest-root storage artifact"
            )
        }
        let artifact = GuestRootStorageReleaseArtifact(sizeBytes: rootArtifact.sizeBytes, sha256: rootArtifact.sha256)
        try requireArtifactIdentity(
            URL(fileURLWithPath: configuration.releaseArtifactPath),
            artifact: artifact,
            resourceName: "Guest release root artifact"
        )
        return artifact
    }

    private static func readProvisioningReceipt(
        _ receiptURL: URL
    ) throws -> GuestRuntimeDiskProvisioningReceipt {
        try requireRegularFile(receiptURL, resourceName: "Guest Runtime disk provisioning receipt")
        do {
            let receipt = try JSONDecoder().decode(
                GuestRuntimeDiskProvisioningReceipt.self,
                from: Data(contentsOf: receiptURL)
            )
            guard receipt.schemaVersion == "v1" else {
                throw GuestRuntimeDiskProvisioningError.failed(
                    "Guest Runtime disk provisioning receipt schemaVersion is invalid"
                )
            }
            return receipt
        } catch let error as GuestRuntimeDiskProvisioningError {
            throw error
        } catch {
            throw GuestRuntimeDiskProvisioningError.unavailable(
                "Guest Runtime disk provisioning receipt cannot be decoded"
            )
        }
    }

    private static func requireArtifactIdentity(
        _ url: URL,
        artifact: GuestRootStorageReleaseArtifact,
        resourceName: String
    ) throws {
        try requireRegularFile(url, resourceName: resourceName)
        let attributes: [FileAttributeKey: Any]
        do {
            attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        } catch {
            throw GuestRuntimeDiskProvisioningError.unavailable(
                "\(resourceName) attributes cannot be read"
            )
        }
        guard let fileSize = attributes[.size] as? NSNumber,
              fileSize.int64Value == artifact.sizeBytes,
              try sha256(of: url) == artifact.sha256
        else {
            throw GuestRuntimeDiskProvisioningError.failed(
                "\(resourceName) does not match the declared immutable release identity"
            )
        }
    }

    private static func requireRegularFile(_ url: URL, resourceName: String) throws {
        do {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular else {
                throw GuestRuntimeDiskProvisioningError.unavailable(
                    "\(resourceName) is not a regular file"
                )
            }
        } catch let error as GuestRuntimeDiskProvisioningError {
            throw error
        } catch {
            throw GuestRuntimeDiskProvisioningError.unavailable(
                "\(resourceName) cannot be read"
            )
        }
    }

    private static func sha256(of url: URL) throws -> String {
        let handle: FileHandle
        do {
            handle = try FileHandle(forReadingFrom: url)
        } catch {
            throw GuestRuntimeDiskProvisioningError.unavailable("Guest artifact cannot be opened for identity verification")
        }
        defer { try? handle.close() }
        var digest = SHA256()
        do {
            while let chunk = try handle.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                digest.update(data: chunk)
            }
        } catch {
            throw GuestRuntimeDiskProvisioningError.unavailable("Guest artifact cannot be read for identity verification")
        }
        return digest.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

// ProvisionedMacOSVirtualMachineFactory is the explicit composition point for
// the Host filesystem provisioning effect and the VZ resource factory. The
// base MacOSVirtualMachineFactory remains responsible only for constructing a
// VZVirtualMachine from an already provisioned C32 attachment.
@available(macOS 13.0, *)
public enum ProvisionedMacOSVirtualMachineFactory {
    public static func makeController(
        document: MacOSVirtualMachineConfigurationDocument
    ) throws -> AppleVirtualMachineController {
        do {
            _ = try GuestRuntimeDiskProvisioner.provision(
                configuration: document.guestRuntimeDiskProvisioning
            )
        } catch let error as GuestRuntimeDiskProvisioningError {
            switch error {
            case .unavailable(let message):
                throw MacOSVirtualMachineConfigurationError.unavailable(
                    "Guest Runtime disk provisioning is unavailable: \(message)"
                )
            case .failed(let message):
                throw MacOSVirtualMachineConfigurationError.invalid(
                    "Guest Runtime disk provisioning failed: \(message)"
                )
            }
        } catch {
            throw MacOSVirtualMachineConfigurationError.unavailable(
                "Guest Runtime disk provisioning failed before macOS VM construction"
            )
        }
        do {
            _ = try GuestBootConsoleCaptureProvisioner.provision(
                capture: document.guestBootConsoleCapture
            )
        } catch let error as GuestBootConsoleCaptureProvisioningError {
            switch error {
            case .unavailable(let message):
                throw MacOSVirtualMachineConfigurationError.unavailable(
                    "Guest boot console capture provisioning is unavailable: \(message)"
                )
            case .failed(let message):
                throw MacOSVirtualMachineConfigurationError.invalid(
                    "Guest boot console capture provisioning failed: \(message)"
                )
            }
        } catch {
            throw MacOSVirtualMachineConfigurationError.unavailable(
                "Guest boot console capture provisioning failed before macOS VM construction"
            )
        }
        return try MacOSVirtualMachineFactory.makeController(document: document)
    }
}

private struct GuestReleaseArtifactManifest: Decodable {
    let schemaVersion: String
    let artifactSetId: String
    let architecture: String
    let storageDevices: [GuestReleaseArtifactManifestStorageDevice]
}

private struct GuestReleaseArtifactManifestStorageDevice: Decodable {
    let id: String
    let role: String
    let storageImageFormat: String
    let guestVolumeFileSystem: String?
    let sizeBytes: Int64
    let sha256: String
}

private struct GuestRootStorageReleaseArtifact: Equatable {
    let sizeBytes: Int64
    let sha256: String
}

private struct GuestRuntimeDiskProvisioningReceipt: Codable {
    let schemaVersion: String
    let releaseArtifactManifestPath: String
    let releaseArtifactPath: String
    let releaseArtifactSizeBytes: Int64
    let releaseArtifactSHA256: String
    let runtimeDiskImagePath: String

    func matches(
        configuration: GuestRuntimeDiskProvisioning,
        releaseArtifact: GuestRootStorageReleaseArtifact
    ) -> Bool {
        schemaVersion == "v1"
            && releaseArtifactManifestPath == configuration.releaseArtifactManifestPath
            && releaseArtifactPath == configuration.releaseArtifactPath
            && releaseArtifactSizeBytes == releaseArtifact.sizeBytes
            && releaseArtifactSHA256 == releaseArtifact.sha256
            && runtimeDiskImagePath == configuration.runtimeDiskImagePath
    }
}

private extension JSONEncoder {
    static var vitalserverSorted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }
}

private func isSHA256(_ value: String) -> Bool {
    value.range(of: "^[0-9a-f]{64}$", options: .regularExpression) != nil
}
