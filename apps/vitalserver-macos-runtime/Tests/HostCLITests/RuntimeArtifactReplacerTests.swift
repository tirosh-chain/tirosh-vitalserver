import Foundation
import Core
import Contracts
@testable import HostCLI
import XCTest

final class RuntimeArtifactReplacerTests: XCTestCase {
    func testReplaceValidatesAndReplacesAppBundleArtifact() throws {
        let stagedBundle = URL(fileURLWithPath: "/bundle")
        let source = stagedBundle.appendingPathComponent("app-bundle.tar.gz")
        var outputs: [URL: String] = [:]
        var events: [String] = []

        let replacer = makeReplacer(
            outputs: { outputs },
            fileSize: { url in
                XCTAssertEqual(url, source)
                return 2_097_152
            },
            fileExists: { url in
                url.path == "/Applications/VitalServer Helper.app"
            },
            directoryExists: { _ in false },
            createDirectory: { url, withIntermediateDirectories in
                events.append("mkdir:\(url.path):\(withIntermediateDirectories)")
            },
            removeItem: { url in
                events.append("rm:\(url.path)")
            },
            moveItem: { source, destination in
                events.append("mv:\(source.path):\(destination.path)")
            },
            runRequired: { executable, arguments in
                events.append("run:\(executable):\(arguments.joined(separator: " "))")
            },
            runProcessToFile: { executable, arguments, output in
                events.append("list:\(executable):\(arguments.joined(separator: " "))")
                if arguments.first == "-tzf" {
                    outputs[output] = "VitalServer Helper.app/Contents/Info.plist\n"
                } else {
                    outputs[output] = "-rw-r--r--  0 user group 0 Jan  1 00:00 VitalServer Helper.app/Contents/Info.plist\n"
                }
            },
            log: { message in events.append("log:\(message)") }
        )

        try replacer.replace([
            UpdateBundleArtifact(name: "app-bundle.tar.gz", type: .appBundle, sha256: "abc", size: 2_097_152),
        ], stagedBundle: stagedBundle)

        XCTAssertTrue(events.contains("rm:/Applications/VitalServer Helper.app"))
        XCTAssertTrue(events.contains("mv:/Applications/.VitalServer Helper.app.update:/Applications/VitalServer Helper.app"))
        XCTAssertTrue(events.contains("run:/usr/bin/tar:-xzf /bundle/app-bundle.tar.gz -C /Applications/.VitalServer Helper.app.update --strip-components 1"))
        XCTAssertTrue(events.contains("log:artifact replacement completed type=app-bundle name=app-bundle.tar.gz"))
    }

    func testReplaceExtractsRuntimeToolsArtifact() throws {
        var outputs: [URL: String] = [:]
        var events: [String] = []
        let replacer = makeReplacer(
            outputs: { outputs },
            createDirectory: { url, _ in events.append("mkdir:\(url.path)") },
            runRequired: { executable, arguments in
                events.append("run:\(executable):\(arguments.joined(separator: " "))")
            },
            runProcessToFile: { _, arguments, output in
                if arguments.first == "-tzf" {
                    outputs[output] = "vitalserver-vm\nvitalserver-proxy-run\ntirosh-vitalserver-uninstall\n"
                } else {
                    outputs[output] = "-rw-r--r-- 0 user group 0 Jan 1 00:00 vitalserver-vm\n"
                }
            }
        )

        try replacer.replace([
            UpdateBundleArtifact(name: "runtime-tools.tar.gz", type: .runtimeTools, sha256: "abc", size: 10),
        ], stagedBundle: URL(fileURLWithPath: "/bundle"))

        XCTAssertTrue(events.contains("mkdir:/usr/local/bin"))
        XCTAssertTrue(events.contains("run:/usr/bin/tar:-xzf /bundle/runtime-tools.tar.gz -C /usr/local/bin"))
    }

    func testReplacePropagatesExistingDestinationPermissionFailure() {
        var outputs: [URL: String] = [:]
        var events: [String] = []
        let replacer = makeReplacer(
            outputs: { outputs },
            fileExists: { $0.path == "/Applications/VitalServer Helper.app" },
            createDirectory: { url, _ in events.append("mkdir:\(url.path)") },
            removeItem: { url in
                events.append("rm:\(url.path)")
                if url.path == "/Applications/VitalServer Helper.app" {
                    throw CocoaError(.fileWriteNoPermission)
                }
            },
            moveItem: { source, destination in
                events.append("mv:\(source.path):\(destination.path)")
            },
            runRequired: { executable, arguments in
                events.append("run:\(executable):\(arguments.joined(separator: " "))")
            },
            runProcessToFile: { _, arguments, output in
                if arguments.first == "-tzf" {
                    outputs[output] = "VitalServer Helper.app/Contents/Info.plist\n"
                } else {
                    outputs[output] = "-rw-r--r-- 0 user group 0 Jan 1 00:00 VitalServer Helper.app/Contents/Info.plist\n"
                }
            }
        )

        XCTAssertThrowsError(try replacer.replace([
            UpdateBundleArtifact(name: "app-bundle.tar.gz", type: .appBundle, sha256: "abc", size: 10),
        ], stagedBundle: URL(fileURLWithPath: "/bundle"))) { error in
            XCTAssertFileWriteNoPermission(error)
        }
        XCTAssertTrue(events.contains("rm:/Applications/VitalServer Helper.app"))
        XCTAssertFalse(events.contains { $0.hasPrefix("mv:") })
    }

    func testReplacePropagatesTemporaryDirectoryPermissionFailure() {
        var outputs: [URL: String] = [:]
        var events: [String] = []
        let replacer = makeReplacer(
            outputs: { outputs },
            createDirectory: { url, _ in
                events.append("mkdir:\(url.path)")
                throw CocoaError(.fileWriteNoPermission)
            },
            runRequired: { executable, _ in events.append("run:\(executable)") },
            runProcessToFile: { _, arguments, output in
                if arguments.first == "-tzf" {
                    outputs[output] = "VitalServer Helper.app/Contents/Info.plist\n"
                } else {
                    outputs[output] = "-rw-r--r-- 0 user group 0 Jan 1 00:00 VitalServer Helper.app/Contents/Info.plist\n"
                }
            }
        )

        XCTAssertThrowsError(try replacer.replace([
            UpdateBundleArtifact(name: "app-bundle.tar.gz", type: .appBundle, sha256: "abc", size: 10),
        ], stagedBundle: URL(fileURLWithPath: "/bundle"))) { error in
            XCTAssertFileWriteNoPermission(error)
        }
        XCTAssertEqual(events, ["mkdir:/Applications/.VitalServer Helper.app.update"])
    }

    func testReplaceRejectsPathTraversalInArchive() {
        var outputs: [URL: String] = [:]
        let replacer = makeReplacer(
            outputs: { outputs },
            runProcessToFile: { _, arguments, output in
                if arguments.first == "-tzf" {
                    outputs[output] = "VitalServer Helper.app/../escape\n"
                } else {
                    outputs[output] = "-rw-r--r-- 0 user group 0 Jan 1 00:00 VitalServer Helper.app/../escape\n"
                }
            }
        )

        XCTAssertThrowsError(try replacer.replace([
            UpdateBundleArtifact(name: "app-bundle.tar.gz", type: .appBundle, sha256: "abc", size: 10),
        ], stagedBundle: URL(fileURLWithPath: "/bundle"))) { error in
            XCTAssertEqual(String(describing: error), String(describing: LauncherError.bundleVerificationFailed(
                "path traversal in app-bundle.tar.gz: VitalServer Helper.app/../escape"
            )))
        }
    }

    func testReplaceRejectsLinksInArchive() {
        var outputs: [URL: String] = [:]
        let replacer = makeReplacer(
            outputs: { outputs },
            runProcessToFile: { _, arguments, output in
                if arguments.first == "-tzf" {
                    outputs[output] = "VitalServer Helper.app/Contents/Info.plist\n"
                } else {
                    outputs[output] = "lrwxr-xr-x 0 user group 0 Jan 1 00:00 VitalServer Helper.app/link\n"
                }
            }
        )

        XCTAssertThrowsError(try replacer.replace([
            UpdateBundleArtifact(name: "app-bundle.tar.gz", type: .appBundle, sha256: "abc", size: 10),
        ], stagedBundle: URL(fileURLWithPath: "/bundle"))) { error in
            XCTAssertEqual(String(describing: error), String(describing: LauncherError.bundleVerificationFailed(
                "tar.gz must not contain links: app-bundle.tar.gz"
            )))
        }
    }

    func testReplaceLogsValidationTemporaryFileCleanupFailures() throws {
        var outputs: [URL: String] = [:]
        var logs: [String] = []
        let replacer = makeReplacer(
            outputs: { outputs },
            removeItem: { url in
                if url.path.hasPrefix("/tmp/tirosh-") {
                    throw CocoaError(.fileWriteNoPermission)
                }
            },
            runProcessToFile: { _, arguments, output in
                if arguments.first == "-tzf" {
                    outputs[output] = "VitalServer Helper.app/Contents/Info.plist\n"
                } else {
                    outputs[output] = "-rw-r--r-- 0 user group 0 Jan 1 00:00 VitalServer Helper.app/Contents/Info.plist\n"
                }
            },
            log: { logs.append($0) }
        )

        try replacer.replace([
            UpdateBundleArtifact(name: "app-bundle.tar.gz", type: .appBundle, sha256: "abc", size: 10),
        ], stagedBundle: URL(fileURLWithPath: "/bundle"))

        XCTAssertEqual(
            logs.filter { $0.contains("artifact validation temporary file cleanup failed") }.count,
            2
        )
    }

    private func makeReplacer(
        outputs: @escaping () -> [URL: String],
        fileSize: @escaping (URL) throws -> UInt64 = { _ in 10 },
        fileExists: @escaping (URL) -> Bool = { _ in false },
        directoryExists: @escaping (URL) -> Bool = { _ in false },
        createDirectory: @escaping (URL, Bool) throws -> Void = { _, _ in },
        removeItem: @escaping (URL) throws -> Void = { _ in },
        moveItem: @escaping (URL, URL) throws -> Void = { _, _ in },
        runRequired: @escaping (String, [String]) throws -> Void = { _, _ in },
        runProcessToFile: @escaping (String, [String], URL) throws -> Void = { _, _, _ in },
        log: @escaping (String) -> Void = { _ in }
    ) -> RuntimeArtifactReplacer {
        RuntimeArtifactReplacer(
            destinations: RuntimeArtifactReplacementDestinations(
                managerApp: URL(fileURLWithPath: "/Applications/VitalServer Helper.app"),
                nginxBundle: URL(fileURLWithPath: "/Library/Application Support/TiroshVitalServer/nginx"),
                guestDeploy: URL(fileURLWithPath: "/Library/Application Support/TiroshVitalServer/vm/data/deploy"),
                runtimeTools: URL(fileURLWithPath: "/usr/local/bin")
            ),
            temporaryDirectory: URL(fileURLWithPath: "/tmp"),
            fileExists: fileExists,
            directoryExists: directoryExists,
            fileSize: fileSize,
            createDirectory: createDirectory,
            removeItem: removeItem,
            moveItem: moveItem,
            readUTF8Text: { url in outputs()[url] ?? "" },
            runRequired: runRequired,
            runProcessToFile: runProcessToFile,
            log: log
        )
    }

    private func XCTAssertFileWriteNoPermission(
        _ error: Error,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let nsError = error as NSError
        XCTAssertEqual(nsError.domain, NSCocoaErrorDomain, file: file, line: line)
        XCTAssertEqual(nsError.code, CocoaError.Code.fileWriteNoPermission.rawValue, file: file, line: line)
    }
}
