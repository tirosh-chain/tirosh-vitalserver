import Foundation
import Application
import Contracts
import Domain
import OutboundAdapters
import InboundAdapters
@testable import CLIHost
import XCTest
import Errors

final class VMRuntimeConfigTests: XCTestCase {
    func testLoadReadsConfigThroughFileStore() throws {
        let fileStore = RuntimeFileStoreSpy()
        let configURL = URL(fileURLWithPath: "/runtime/vm-config.json")
        let expected = VMRuntimeConfig(
            cpuCount: 4,
            memoryMiB: 4096,
            kernelPath: "/runtime/kernel",
            initialRamdiskPath: "/runtime/initrd",
            diskPath: "/runtime/disk.img",
            cloudInitPath: nil,
            kernelCommandLine: "console=hvc0",
            network: NetworkConfig(mode: .shared, bridgedInterface: nil, macAddress: "02:00:00:00:00:01"),
            sharedDirectory: nil,
            vitalFilesDirectory: nil
        )
        fileStore.files[configURL] = try JSONEncoder().encode(expected)

        let loaded = try VMRuntimeConfig.load(from: configURL, fileStore: fileStore)

        XCTAssertEqual(loaded.cpuCount, expected.cpuCount)
        XCTAssertEqual(loaded.memoryMiB, expected.memoryMiB)
        XCTAssertEqual(loaded.kernelPath, expected.kernelPath)
        XCTAssertEqual(loaded.network.macAddress, expected.network.macAddress)
    }

    func testLoadPreservesMissingSSHAuthorizedKeysAsMissingState() throws {
        let fileStore = RuntimeFileStoreSpy()
        let configURL = URL(fileURLWithPath: "/runtime/vm-config.json")
        fileStore.files[configURL] = Data("""
        {
          "cpuCount": 4,
          "memoryMiB": 4096,
          "kernelPath": "/runtime/kernel",
          "kernelCommandLine": "console=hvc0",
          "network": {
            "mode": "shared"
          }
        }
        """.utf8)

        let loaded = try VMRuntimeConfig.load(from: configURL, fileStore: fileStore)

        XCTAssertNil(loaded.sshAuthorizedKeys)
    }

    func testLoadPreservesConfigPathInspectionFailure() {
        let fileStore = RuntimeFileStoreSpy()
        let configURL = URL(fileURLWithPath: "/runtime/vm-config.json")
        fileStore.pathStates[configURL.path] = .inspectFailed("permission denied")

        XCTAssertThrowsError(try VMRuntimeConfig.load(from: configURL, fileStore: fileStore)) { error in
            guard case LauncherError.runtimeOperationFailed(let message) = error else {
                return XCTFail("expected runtimeOperationFailed, got \(error)")
            }
            XCTAssertEqual(
                message,
                "VM config path inspection failed path=/runtime/vm-config.json reason=permission denied"
            )
        }
    }

    func testLoadPreservesUnexpectedConfigPathState() {
        let fileStore = RuntimeFileStoreSpy()
        let configURL = URL(fileURLWithPath: "/runtime/vm-config.json")
        fileStore.pathStates[configURL.path] = .directory

        XCTAssertThrowsError(try VMRuntimeConfig.load(from: configURL, fileStore: fileStore)) { error in
            guard case LauncherError.runtimeOperationFailed(let message) = error else {
                return XCTFail("expected runtimeOperationFailed, got \(error)")
            }
            XCTAssertEqual(
                message,
                "VM config path state is unexpected path=/runtime/vm-config.json state=directory"
            )
        }
    }

    func testEnsureRuntimeDefaultsWritesExplicitEmptySSHAuthorizedKeysWhenMissing() {
        let paths = InstalledRuntimePaths(runtimeHome: URL(fileURLWithPath: "/runtime-root"))
        var config = VMRuntimeConfig.default(paths: paths)
        config.sshAuthorizedKeys = nil

        VMRuntimeConfig.ensureRuntimeDefaults(&config, paths: paths)

        XCTAssertEqual(config.sshAuthorizedKeys, [])
    }

    func testEnsureRuntimeDefaultsNormalizesKernelGuardsForExistingConfig() {
        let paths = InstalledRuntimePaths(runtimeHome: URL(fileURLWithPath: "/runtime-root"))
        var config = VMRuntimeConfig.default(paths: paths)
        config.kernelCommandLine = "console=hvc0 root=/dev/vda1 rw bpf_jit_enable=1"

        VMRuntimeConfig.ensureRuntimeDefaults(&config, paths: paths)

        XCTAssertEqual(config.kernelCommandLine, "console=hvc0 rw root=LABEL=cloudimg-rootfs seccomp=0")
    }

    func testValidateBootFilesUsesFileStoreExistence() throws {
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[URL(fileURLWithPath: "/runtime/kernel")] = Data()
        fileStore.files[URL(fileURLWithPath: "/runtime/initrd")] = Data()
        fileStore.files[URL(fileURLWithPath: "/runtime/disk.img")] = Data()
        let config = VMRuntimeConfig(
            cpuCount: 4,
            memoryMiB: 4096,
            kernelPath: "/runtime/kernel",
            initialRamdiskPath: "/runtime/initrd",
            diskPath: "/runtime/disk.img",
            cloudInitPath: nil,
            kernelCommandLine: "console=hvc0",
            network: NetworkConfig(mode: .shared, bridgedInterface: nil, macAddress: nil),
            sharedDirectory: nil,
            vitalFilesDirectory: nil
        )

        XCTAssertNoThrow(try VMRuntimeConfig.validateBootFiles(config, fileStore: fileStore))
    }

    func testValidateBootFilesReportsMissingPath() {
        let fileStore = RuntimeFileStoreSpy()
        let config = VMRuntimeConfig(
            cpuCount: 4,
            memoryMiB: 4096,
            kernelPath: "/runtime/kernel",
            initialRamdiskPath: nil,
            diskPath: nil,
            cloudInitPath: nil,
            kernelCommandLine: "console=hvc0",
            network: NetworkConfig(mode: .shared, bridgedInterface: nil, macAddress: nil),
            sharedDirectory: nil,
            vitalFilesDirectory: nil
        )

        XCTAssertThrowsError(try VMRuntimeConfig.validateBootFiles(config, fileStore: fileStore)) { error in
            guard case LauncherError.missingFile("/runtime/kernel") = error else {
                return XCTFail("expected missingFile, got \(error)")
            }
        }
    }

    func testValidateBootFilesPreservesPathInspectionFailure() {
        let fileStore = RuntimeFileStoreSpy()
        fileStore.pathStates["/runtime/kernel"] = .inspectFailed("permission denied")
        let config = VMRuntimeConfig(
            cpuCount: 4,
            memoryMiB: 4096,
            kernelPath: "/runtime/kernel",
            initialRamdiskPath: nil,
            diskPath: nil,
            cloudInitPath: nil,
            kernelCommandLine: "console=hvc0",
            network: NetworkConfig(mode: .shared, bridgedInterface: nil, macAddress: nil),
            sharedDirectory: nil,
            vitalFilesDirectory: nil
        )

        XCTAssertThrowsError(try VMRuntimeConfig.validateBootFiles(config, fileStore: fileStore)) { error in
            guard case LauncherError.runtimeOperationFailed(let message) = error else {
                return XCTFail("expected runtimeOperationFailed, got \(error)")
            }
            XCTAssertEqual(
                message,
                "VM boot file path inspection failed path=/runtime/kernel reason=permission denied"
            )
        }
    }

    func testValidateBootFilesPreservesUnexpectedPathState() {
        let fileStore = RuntimeFileStoreSpy()
        fileStore.pathStates["/runtime/kernel"] = .directory
        let config = VMRuntimeConfig(
            cpuCount: 4,
            memoryMiB: 4096,
            kernelPath: "/runtime/kernel",
            initialRamdiskPath: nil,
            diskPath: nil,
            cloudInitPath: nil,
            kernelCommandLine: "console=hvc0",
            network: NetworkConfig(mode: .shared, bridgedInterface: nil, macAddress: nil),
            sharedDirectory: nil,
            vitalFilesDirectory: nil
        )

        XCTAssertThrowsError(try VMRuntimeConfig.validateBootFiles(config, fileStore: fileStore)) { error in
            guard case LauncherError.runtimeOperationFailed(let message) = error else {
                return XCTFail("expected runtimeOperationFailed, got \(error)")
            }
            XCTAssertEqual(
                message,
                "VM boot file path state is unexpected path=/runtime/kernel state=directory"
            )
        }
    }

    func testConfigurationFactoryRejectsMissingExplicitCloudInitStoragePath() {
        let fileStore = RuntimeFileStoreSpy()
        let factory = VMConfigurationFactory(
            fileStore: fileStore,
            detached: true,
            serialInput: FileHandle.standardInput,
            serialOutput: FileHandle.standardOutput
        )
        let config = factoryConfig(cloudInitPath: "/runtime/cloud-init.iso")

        XCTAssertThrowsError(try factory.build(from: config)) { error in
            XCTAssertEqual(error as? VMConfigurationFactoryError, .missingStorageFile("/runtime/cloud-init.iso"))
        }
    }

    func testConfigurationFactoryRejectsCloudInitStoragePathInspectionFailure() {
        let fileStore = RuntimeFileStoreSpy()
        fileStore.pathStates["/runtime/cloud-init.iso"] = .inspectFailed("permission denied")
        let factory = VMConfigurationFactory(
            fileStore: fileStore,
            detached: true,
            serialInput: FileHandle.standardInput,
            serialOutput: FileHandle.standardOutput
        )
        let config = factoryConfig(cloudInitPath: "/runtime/cloud-init.iso")

        XCTAssertThrowsError(try factory.build(from: config)) { error in
            XCTAssertEqual(
                error as? VMConfigurationFactoryError,
                .storagePathInspectionFailed(path: "/runtime/cloud-init.iso", reason: "permission denied")
            )
        }
    }

    func testConfigurationFactoryRejectsUnexpectedCloudInitStoragePathState() {
        let fileStore = RuntimeFileStoreSpy()
        fileStore.pathStates["/runtime/cloud-init.iso"] = .directory
        let factory = VMConfigurationFactory(
            fileStore: fileStore,
            detached: true,
            serialInput: FileHandle.standardInput,
            serialOutput: FileHandle.standardOutput
        )
        let config = factoryConfig(cloudInitPath: "/runtime/cloud-init.iso")

        XCTAssertThrowsError(try factory.build(from: config)) { error in
            XCTAssertEqual(
                error as? VMConfigurationFactoryError,
                .unexpectedStoragePathState(path: "/runtime/cloud-init.iso", state: "directory")
            )
        }
    }

    func testConfigurationFactoryUsesDurableStoragePolicyForWritableRootDisk() throws {
        let source = try readRuntimeSourceFile(
            "Adapters/Outbound/VirtualMachine/VMConfigurationFactory.swift"
        )

        XCTAssertTrue(source.contains("readOnly: false,\n                cachingMode: .uncached,"))
        XCTAssertTrue(source.contains("synchronizationMode: .full"))
        XCTAssertTrue(source.contains("VZNVMExpressControllerDeviceConfiguration(attachment: attachment)"))
    }

    private func factoryConfig(
        diskPath: String? = nil,
        cloudInitPath: String?
    ) -> VMRuntimeConfig {
        VMRuntimeConfig(
            cpuCount: 4,
            memoryMiB: 4096,
            kernelPath: "/runtime/kernel",
            initialRamdiskPath: nil,
            diskPath: diskPath,
            cloudInitPath: cloudInitPath,
            kernelCommandLine: "console=hvc0",
            network: NetworkConfig(mode: .shared, bridgedInterface: nil, macAddress: nil),
            sharedDirectory: nil,
            vitalFilesDirectory: nil
        )
    }

    private func readRuntimeSourceFile(_ relativePath: String) throws -> String {
        var current = URL(fileURLWithPath: #filePath)
        while current.path != "/" {
            let candidate = current
                .appendingPathComponent("apps/vitalserver-macos-runtime/Sources")
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(
                    contentsOf: candidate.appendingPathComponent(relativePath),
                    encoding: .utf8
                )
            }
            current.deleteLastPathComponent()
        }
        throw NSError(domain: "VMRuntimeConfigTests", code: 1)
    }
}
