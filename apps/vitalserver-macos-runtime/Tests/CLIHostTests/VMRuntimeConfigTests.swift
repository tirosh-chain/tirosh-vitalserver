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

    func testEnsureRuntimeDefaultsWritesExplicitEmptySSHAuthorizedKeysWhenMissing() {
        let paths = InstalledRuntimePaths(runtimeHome: URL(fileURLWithPath: "/runtime-root"))
        var config = VMRuntimeConfig.default(paths: paths)
        config.sshAuthorizedKeys = nil

        VMRuntimeConfig.ensureRuntimeDefaults(&config, paths: paths)

        XCTAssertEqual(config.sshAuthorizedKeys, [])
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
}
