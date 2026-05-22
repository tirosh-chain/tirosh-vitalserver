import Foundation
@testable import RuntimeOrchestrator
import XCTest

final class RuntimeVersionStoreTests: XCTestCase {
    func testWriteInstalledVersionWritesInstalledRuntimeDocument() throws {
        var createdDirectories: [String] = []
        var writtenFiles: [String: String] = [:]
        let store = makeStore(
            createDirectory: { url, withIntermediateDirectories in
                createdDirectories.append("\(url.path):\(withIntermediateDirectories)")
            },
            writeData: { data, url in
                writtenFiles[url.path] = String(data: data, encoding: .utf8)
            }
        )

        try store.writeInstalledVersion(version: "0.1.4")

        XCTAssertEqual(createdDirectories, ["/product/vm/runtime:true"])
        let document = try XCTUnwrap(writtenFiles["/product/vm/runtime/runtime-version.json"])
        XCTAssertTrue(document.contains(#""product" : "TiroshVitalServer""#))
        XCTAssertTrue(document.contains(#""runtimeVersion" : "0.1.4""#))
        XCTAssertTrue(document.contains(#""installedAt" : "2026-05-22T01:02:03Z""#))
        XCTAssertTrue(document.contains(#""rootfsBase" : "rootfs-base.raw.gz""#))
        XCTAssertTrue(document.contains(#""vmDisk" : "vm-disk.img""#))
    }

    func testWriteAppliedVersionWritesBundleRuntimeDocument() throws {
        var writtenFiles: [String: String] = [:]
        let store = makeStore(
            writeData: { data, url in
                writtenFiles[url.path] = String(data: data, encoding: .utf8)
            }
        )

        try store.writeAppliedVersion(
            version: "0.1.5",
            bundle: URL(fileURLWithPath: "/bundles/update-bundle-0.1.5")
        )

        let document = try XCTUnwrap(writtenFiles["/product/vm/runtime/runtime-version.json"])
        XCTAssertTrue(document.contains(#""runtimeVersion" : "0.1.5""#))
        XCTAssertTrue(document.contains(#""appliedAt" : "2026-05-22T01:02:03Z""#))
        XCTAssertTrue(document.contains(#""bundle" : "update-bundle-0.1.5""#))
    }

    func testReadVersionValueReturnsStoredVersion() {
        let store = makeStore(
            fileExists: { _ in true },
            readData: { _ in Data(#"{"runtimeVersion":"0.1.6"}"#.utf8) }
        )

        XCTAssertEqual(store.readVersionValue(default: "unknown"), "0.1.6")
    }

    func testReadVersionValueReturnsDefaultWhenFileIsMissingOrInvalid() {
        let missing = makeStore(fileExists: { _ in false })
        let invalid = makeStore(
            fileExists: { _ in true },
            readData: { _ in Data(#"{"runtimeVersion":7}"#.utf8) }
        )

        XCTAssertEqual(missing.readVersionValue(default: "unknown"), "unknown")
        XCTAssertEqual(invalid.readVersionValue(default: "unknown"), "unknown")
    }

    private func makeStore(
        fileExists: @escaping (URL) -> Bool = { _ in false },
        createDirectory: @escaping (URL, Bool) throws -> Void = { _, _ in },
        readData: @escaping (URL) throws -> Data = { _ in Data() },
        writeData: @escaping (Data, URL) throws -> Void = { _, _ in }
    ) -> RuntimeVersionStore {
        RuntimeVersionStore(
            versionFile: URL(fileURLWithPath: "/product/vm/runtime/runtime-version.json"),
            timestamp: { "2026-05-22T01:02:03Z" },
            fileExists: fileExists,
            createDirectory: createDirectory,
            readData: readData,
            writeData: writeData
        )
    }
}
