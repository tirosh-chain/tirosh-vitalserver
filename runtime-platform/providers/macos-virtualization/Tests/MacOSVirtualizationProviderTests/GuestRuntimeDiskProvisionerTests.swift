import CryptoKit
import Foundation
import Testing
@testable import MacOSVirtualizationProvider

private struct GuestRuntimeDiskProvisioningFixture {
    let directory: URL
    let releaseManifestURL: URL
    let releaseArtifactURL: URL
    let runtimeDiskURL: URL
    let receiptURL: URL
    let configuration: GuestRuntimeDiskProvisioning
}

private func guestRuntimeDiskProvisioningFixture() throws -> GuestRuntimeDiskProvisioningFixture {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("vitalserver-guest-runtime-disk-provisioning-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    let releaseArtifactURL = directory.appendingPathComponent("release/guest-root.raw")
    try FileManager.default.createDirectory(at: releaseArtifactURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    let releaseBytes = Data("immutable-release-root".utf8)
    try releaseBytes.write(to: releaseArtifactURL)
    let releaseSHA256 = SHA256.hash(data: releaseBytes).map { String(format: "%02x", $0) }.joined()
    let releaseManifestURL = directory.appendingPathComponent("release/macos-guest-artifact-manifest.json")
    let manifest: [String: Any] = [
        "schemaVersion": "v1",
        "artifactSetId": "vitalserver-guest-runtime-disk-provisioning-test",
        "architecture": "arm64",
        "storageDevices": [[
            "id": "guest-root",
            "role": "guest-root-storage",
            "storageImageFormat": "raw",
            "sizeBytes": releaseBytes.count,
            "sha256": releaseSHA256,
        ]],
    ]
    try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys]).write(to: releaseManifestURL)
    let runtimeDiskURL = directory.appendingPathComponent("data/vm/guest-root.raw")
    let receiptURL = directory.appendingPathComponent("data/vm/guest-root-provisioning-receipt.json")
    return GuestRuntimeDiskProvisioningFixture(
        directory: directory,
        releaseManifestURL: releaseManifestURL,
        releaseArtifactURL: releaseArtifactURL,
        runtimeDiskURL: runtimeDiskURL,
        receiptURL: receiptURL,
        configuration: GuestRuntimeDiskProvisioning(
            releaseArtifactManifestPath: releaseManifestURL.path,
            releaseArtifactPath: releaseArtifactURL.path,
            runtimeDiskImagePath: runtimeDiskURL.path,
            provisioningReceiptPath: receiptURL.path,
            existingRuntimeDiskPolicy: "retain-when-receipt-matches-release-artifact"
        )
    )
}

@Test("Guest Runtime disk provisioner creates a separate runtime disk and retains it only with matching receipt")
func guestRuntimeDiskProvisionerCreatesAndRetainsExplicitWorkspace() throws {
    let fixture = try guestRuntimeDiskProvisioningFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }

    #expect(try GuestRuntimeDiskProvisioner.provision(configuration: fixture.configuration) == .provisioned)
    #expect(try Data(contentsOf: fixture.runtimeDiskURL) == Data(contentsOf: fixture.releaseArtifactURL))
    #expect(FileManager.default.fileExists(atPath: fixture.receiptURL.path))

    try Data("Guest-owned runtime change".utf8).write(to: fixture.runtimeDiskURL)
    #expect(try GuestRuntimeDiskProvisioner.provision(configuration: fixture.configuration) == .retainedExistingRuntimeDisk)
    #expect(try Data(contentsOf: fixture.runtimeDiskURL) == Data("Guest-owned runtime change".utf8))
    #expect(try Data(contentsOf: fixture.releaseArtifactURL) == Data("immutable-release-root".utf8))
}

@Test("Guest Runtime disk provisioner rejects an existing disk without its matching receipt")
func guestRuntimeDiskProvisionerRejectsUnprovenExistingWorkspace() throws {
    let fixture = try guestRuntimeDiskProvisioningFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    try FileManager.default.createDirectory(at: fixture.runtimeDiskURL.deletingLastPathComponent(), withIntermediateDirectories: true)
    try Data("unknown-existing-runtime-disk".utf8).write(to: fixture.runtimeDiskURL)

    do {
        _ = try GuestRuntimeDiskProvisioner.provision(configuration: fixture.configuration)
        Issue.record("expected Guest Runtime disk provisioning to reject an existing workspace without receipt")
    } catch let error as GuestRuntimeDiskProvisioningError {
        #expect(error.localizedDescription.contains("must either both exist or both be absent"))
    }
}

@Test("Guest Runtime disk provisioner requires an arm64 C34 release identity")
func guestRuntimeDiskProvisionerRejectsWrongArchitectureGuestReleaseManifest() throws {
    let fixture = try guestRuntimeDiskProvisioningFixture()
    defer { try? FileManager.default.removeItem(at: fixture.directory) }
    var manifest = try #require(
        JSONSerialization.jsonObject(with: Data(contentsOf: fixture.releaseManifestURL))
            as? [String: Any]
    )
    manifest["architecture"] = "amd64"
    try JSONSerialization.data(withJSONObject: manifest, options: [.sortedKeys])
        .write(to: fixture.releaseManifestURL)

    do {
        _ = try GuestRuntimeDiskProvisioner.provision(configuration: fixture.configuration)
        Issue.record("expected Guest Runtime disk provisioning to reject a non-arm64 C34 release manifest")
    } catch let error as GuestRuntimeDiskProvisioningError {
        #expect(error.localizedDescription.contains("does not declare one valid guest-root"))
    }
}
