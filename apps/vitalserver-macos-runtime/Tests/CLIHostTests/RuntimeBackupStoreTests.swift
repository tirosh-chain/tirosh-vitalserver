import Foundation
import Bootstrap
import Application
import Contracts
import Domain
import OutboundAdapters
@testable import CLIHost
import XCTest
import Errors

final class RuntimeBackupStoreTests: XCTestCase {
    func testManagedBackupArtifactPolicyMapsUpdateArtifactsAndDestinations() {
        let paths = makePaths()
        let backup = URL(fileURLWithPath: "/backup")

        XCTAssertEqual(
            RuntimeManagedBackupArtifact.allCases.map(\.updateArtifactType),
            [.appBundle, .nginxBundle, .guestDeploy, .runtimeTools]
        )
        XCTAssertEqual(
            RuntimeManagedBackupArtifact.directoryArtifacts.map(\.updateArtifactType),
            [.appBundle, .nginxBundle, .guestDeploy]
        )
        XCTAssertEqual(RuntimeManagedBackupArtifact.appBundle.source(in: paths), paths.managerApp)
        XCTAssertEqual(RuntimeManagedBackupArtifact.nginxBundle.source(in: paths), paths.nginxBundle)
        XCTAssertEqual(RuntimeManagedBackupArtifact.guestDeploy.source(in: paths), paths.guestDeploy)
        XCTAssertEqual(RuntimeManagedBackupArtifact.runtimeTools.source(in: paths), paths.runtimeTools)
        XCTAssertEqual(
            RuntimeManagedBackupArtifact.guestDeploy.backupPath(in: backup).path,
            "/backup/guest-deploy"
        )
        XCTAssertEqual(
            RuntimeManagedBackupArtifact.nginxBundle.restoreDestination(
                managerAppPath: paths.managerApp,
                nginxDirectory: paths.nginxBundle,
                deployDirectory: paths.guestDeploy,
                runtimeToolsDirectory: paths.runtimeTools
            ),
            paths.nginxBundle
        )
    }

    func testCreateBackupCopiesManagedArtifactsAndWritesManifest() throws {
        var createdDirectories: [String] = []
        var copiedItems: [String] = []
        var writtenFiles: [String: String] = [:]
        var logs: [String] = []
        let paths = makePaths()

        let store = makeStore(
            paths: paths,
            fileExists: { url in
                [
                    paths.rootfsBase.path,
                    paths.runtimeVersion.path,
                    Constants.InstallPaths.vmBin,
                    Constants.InstallPaths.proxyRun,
                    Constants.InstallPaths.uninstall,
                ].contains(url.path)
            },
            directoryExists: { url in
                [
                    paths.managerApp.path,
                    paths.nginxBundle.path,
                    paths.guestDeploy.path,
                ].contains(url.path)
            },
            createDirectory: { url, withIntermediateDirectories in
                createdDirectories.append("\(url.path):\(withIntermediateDirectories)")
            },
            copyItem: { source, destination in
                copiedItems.append("\(source.path)->\(destination.path)")
            },
            writeData: { data, url in
                writtenFiles[url.path] = String(data: data, encoding: .utf8)
            },
            log: { logs.append($0) }
        )

        let backup = try store.createBackup(reason: "before-0.1.4")

        XCTAssertEqual(backup.path, "/product/backups/20260522T010203Z-before-0.1.4")
        XCTAssertTrue(createdDirectories.contains("/product/backups/20260522T010203Z-before-0.1.4:true"))
        XCTAssertTrue(createdDirectories.contains("/product/backups/20260522T010203Z-before-0.1.4/runtime-tools:true"))
        XCTAssertTrue(copiedItems.contains("/product/vm/runtime/rootfs-base.raw.gz->/product/backups/20260522T010203Z-before-0.1.4/rootfs-base.raw.gz"))
        XCTAssertTrue(copiedItems.contains("/product/vm/runtime/runtime-version.json->/product/backups/20260522T010203Z-before-0.1.4/runtime-version.json"))
        XCTAssertTrue(copiedItems.contains("/Applications/VitalServer Helper.app->/product/backups/20260522T010203Z-before-0.1.4/app-bundle"))
        XCTAssertTrue(copiedItems.contains("/product/nginx->/product/backups/20260522T010203Z-before-0.1.4/nginx-bundle"))
        XCTAssertTrue(copiedItems.contains("/product/vm/data/deploy->/product/backups/20260522T010203Z-before-0.1.4/guest-deploy"))
        XCTAssertTrue(copiedItems.contains("/usr/local/bin/vitalserver-vm->/product/backups/20260522T010203Z-before-0.1.4/runtime-tools/vitalserver-vm"))
        XCTAssertTrue(copiedItems.contains("/usr/local/bin/vitalserver-proxy-run->/product/backups/20260522T010203Z-before-0.1.4/runtime-tools/vitalserver-proxy-run"))
        XCTAssertTrue(copiedItems.contains("/usr/local/bin/tirosh-vitalserver-uninstall->/product/backups/20260522T010203Z-before-0.1.4/runtime-tools/tirosh-vitalserver-uninstall"))
        XCTAssertTrue(logs.contains("backup rootfs-base source=/product/vm/runtime/rootfs-base.raw.gz"))
        XCTAssertTrue(logs.contains("backup runtime-version source=/product/vm/runtime/runtime-version.json"))

        let manifestPath = "/product/backups/20260522T010203Z-before-0.1.4/backup-manifest.json"
        let manifest = try XCTUnwrap(writtenFiles[manifestPath])
        XCTAssertTrue(manifest.contains(#""product" : "ai.tirosh.vitalserver.helper""#))
        XCTAssertTrue(manifest.contains(#""createdAt" : "2026-05-22T01:02:03Z""#))
        XCTAssertTrue(manifest.contains(#""reason" : "before-0.1.4""#))
        XCTAssertTrue(manifest.contains(#""rootfsBase" : "rootfs-base.raw.gz""#))
        XCTAssertTrue(manifest.contains(#""vmDiskPreserved" : true"#))
    }

    func testCreateBackupManifestOmitsRootfsWhenSourceIsMissing() throws {
        var writtenFiles: [String: String] = [:]
        let paths = makePaths()
        let store = makeStore(
            paths: paths,
            fileExists: { url in url == paths.runtimeVersion },
            writeData: { data, url in
                writtenFiles[url.path] = String(data: data, encoding: .utf8)
            }
        )

        _ = try store.createBackup(reason: "before-0.1.4")

        let manifestPath = "/product/backups/20260522T010203Z-before-0.1.4/backup-manifest.json"
        let manifest = try XCTUnwrap(writtenFiles[manifestPath])
        XCTAssertFalse(manifest.contains(#""rootfsBase""#))
    }

    func testRestoreBackupPathReplacesExistingDestination() throws {
        var events: [String] = []
        let source = URL(fileURLWithPath: "/backup/app-bundle")
        let destination = URL(fileURLWithPath: "/Applications/VitalServer Helper.app")
        let store = makeStore(
            fileExists: { url in url == source },
            directoryExists: { url in url == destination },
            copyItem: { source, destination in
                events.append("copy:\(source.path)->\(destination.path)")
            },
            removeItem: { url in events.append("remove:\(url.path)") }
        )

        try store.restoreBackupPathIfExists(source, to: destination)

        XCTAssertEqual(events, [
            "remove:/Applications/VitalServer Helper.app",
            "copy:/backup/app-bundle->/Applications/VitalServer Helper.app",
        ])
    }

    func testRestoreBackupPathSkipsMissingSource() throws {
        var events: [String] = []
        let store = makeStore(
            copyItem: { _, _ in events.append("copy") },
            removeItem: { _ in events.append("remove") }
        )

        try store.restoreBackupPathIfExists(
            URL(fileURLWithPath: "/backup/missing"),
            to: URL(fileURLWithPath: "/destination")
        )

        XCTAssertTrue(events.isEmpty)
    }

    func testRestoreRuntimeToolsCopiesAndChmodsTools() throws {
        let source = URL(fileURLWithPath: "/backup/runtime-tools")
        var events: [String] = []
        let store = makeStore(
            fileExists: { url in url.path == "/usr/local/bin/vitalserver-vm" },
            directoryExists: { url in url == source },
            copyItem: { source, destination in
                events.append("copy:\(source.path)->\(destination.path)")
            },
            removeItem: { url in events.append("remove:\(url.path)") },
            contentsOfDirectory: { url in
                XCTAssertEqual(url, source)
                return [
                    source.appendingPathComponent("vitalserver-vm"),
                    source.appendingPathComponent("vitalserver-proxy-run"),
                ]
            },
            chmodExecutable: { url in events.append("chmod:\(url.path)") }
        )

        try store.restoreRuntimeToolsIfExists(source)

        XCTAssertEqual(events, [
            "remove:/usr/local/bin/vitalserver-vm",
            "copy:/backup/runtime-tools/vitalserver-vm->/usr/local/bin/vitalserver-vm",
            "chmod:/usr/local/bin/vitalserver-vm",
            "copy:/backup/runtime-tools/vitalserver-proxy-run->/usr/local/bin/vitalserver-proxy-run",
            "chmod:/usr/local/bin/vitalserver-proxy-run",
        ])
    }

    func testLatestBackupSelectsNewestManagedBeforeBackup() throws {
        let store = makeStore(
            directoryExists: { url in
                url.path == "/product/backups"
            },
            childDirectories: { url, nameContains in
                XCTAssertEqual(url.path, "/product/backups")
                XCTAssertEqual(nameContains, "-before-")
                return [
                    URL(fileURLWithPath: "/product/backups/20260521T000000Z-before-0.1.2"),
                    URL(fileURLWithPath: "/product/backups/20260522T000000Z-before-0.1.3"),
                ]
            }
        )

        XCTAssertEqual(try store.latestBackup()?.path, "/product/backups/20260522T000000Z-before-0.1.3")
    }

    func testLatestBackupTreatsMissingBackupDirectoryAsNoBackupWithoutReadFailure() throws {
        let store = makeStore(
            directoryExists: { _ in false },
            childDirectories: { _, _ in
                XCTFail("missing backup directory must not be read")
                return []
            }
        )

        XCTAssertNil(try store.latestBackup())
    }

    func testLatestBackupPropagatesReadFailure() {
        let store = makeStore(
            directoryExists: { url in
                url.path == "/product/backups"
            },
            childDirectories: { _, _ in
                throw NSError(domain: "backup-read", code: 1)
            }
        )

        XCTAssertThrowsError(try store.latestBackup())
    }

    func testRequireLatestBackupFailsWhenNoneExists() {
        let store = makeStore(childDirectories: { _, _ in [] })

        XCTAssertThrowsError(try store.requireLatestBackup()) { error in
            XCTAssertEqual(error as? RuntimeBackupStoreError, .noBackupsAvailable)
        }
    }

    private func makePaths() -> RuntimeBackupStorePaths {
        RuntimeBackupStorePaths(
            backupsDirectory: URL(fileURLWithPath: "/product/backups"),
            rootfsBase: URL(fileURLWithPath: "/product/vm/runtime/rootfs-base.raw.gz"),
            runtimeVersion: URL(fileURLWithPath: "/product/vm/runtime/runtime-version.json"),
            managerApp: URL(fileURLWithPath: "/Applications/VitalServer Helper.app"),
            nginxBundle: URL(fileURLWithPath: "/product/nginx"),
            guestDeploy: URL(fileURLWithPath: "/product/vm/data/deploy"),
            runtimeTools: URL(fileURLWithPath: "/usr/local/bin")
        )
    }

    private func makeStore(
        paths: RuntimeBackupStorePaths? = nil,
        fileExists: @escaping (URL) -> Bool = { _ in false },
        directoryExists: @escaping (URL) -> Bool = { _ in false },
        createDirectory: @escaping (URL, Bool) throws -> Void = { _, _ in },
        copyItem: @escaping (URL, URL) throws -> Void = { _, _ in },
        removeItem: @escaping (URL) throws -> Void = { _ in },
        writeData: @escaping (Data, URL) throws -> Void = { _, _ in },
        contentsOfDirectory: @escaping (URL) throws -> [URL] = { _ in [] },
        childDirectories: @escaping (URL, String) throws -> [URL] = { _, _ in [] },
        chmodExecutable: @escaping (URL) throws -> Void = { _ in },
        log: @escaping (String) -> Void = { _ in }
    ) -> RuntimeBackupStore {
        RuntimeBackupStore(
            paths: paths ?? makePaths(),
            metadata: RuntimeBackupStoreMetadata(
                productIdentifier: "ai.tirosh.vitalserver.helper",
                rootfsBaseName: "rootfs-base.raw.gz",
                runtimeVersionName: "runtime-version.json",
                backupManifestName: "backup-manifest.json",
                vmDiskName: "vm-disk.img",
                runtimeToolPaths: [
                    URL(fileURLWithPath: Constants.InstallPaths.vmBin),
                    URL(fileURLWithPath: Constants.InstallPaths.proxyRun),
                    URL(fileURLWithPath: Constants.InstallPaths.uninstall),
                ]
            ),
            timestamp: { "20260522T010203Z" },
            isoTimestamp: { "2026-05-22T01:02:03Z" },
            fileExists: fileExists,
            directoryExists: directoryExists,
            createDirectory: createDirectory,
            copyItem: copyItem,
            removeItem: removeItem,
            writeData: writeData,
            contentsOfDirectory: contentsOfDirectory,
            childDirectories: childDirectories,
            chmodExecutable: chmodExecutable,
            log: log
        )
    }
}
