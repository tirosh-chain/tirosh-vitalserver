import Application
import Contracts
import Foundation
import OutboundAdapters
import XCTest

final class RuntimeVMLifecycleStoreTests: XCTestCase {
    func testWriteStartingCreatesNewLifecycleDocumentWhenMissing() throws {
        let harness = try Harness()
        defer { harness.cleanup() }

        try harness.store.write(
            state: .starting,
            operation: .startServices,
            message: "VM process start requested",
            bootWindowSeconds: 600
        )

        let document = try harness.readDocument()
        XCTAssertEqual(document.state, .starting)
        XCTAssertEqual(document.operation, .startServices)
        XCTAssertEqual(document.startedAt, "2026-06-07T00:01:00Z")
        XCTAssertEqual(document.updatedAt, "2026-06-07T00:01:00Z")
        XCTAssertEqual(document.deadlineAt, "2026-06-07T00:11:00Z")
        XCTAssertEqual(document.message, "VM process start requested")
    }

    func testWriteRunningDoesNotCreateLifecycleFromMissingDocument() throws {
        let harness = try Harness()
        defer { harness.cleanup() }

        XCTAssertThrowsError(try harness.store.write(state: .running, message: "VM is running")) { error in
            XCTAssertEqual(error as? RuntimeVMLifecycleStoreError, .missingDocumentForState(.running))
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: harness.url.path))
    }

    func testWritePreservesExistingStartedAtWhenAdvancingLifecycle() throws {
        let harness = try Harness()
        defer { harness.cleanup() }
        try harness.writeDocument(RuntimeVMLifecycleDocument(
            state: .starting,
            startedAt: "2026-06-07T00:00:00Z",
            updatedAt: "2026-06-07T00:00:01Z"
        ))

        try harness.store.write(state: .running, message: "VM is running")

        let document = try harness.readDocument()
        XCTAssertEqual(document.state, .running)
        XCTAssertEqual(document.startedAt, "2026-06-07T00:00:00Z")
        XCTAssertEqual(document.updatedAt, "2026-06-07T00:01:00Z")
        XCTAssertEqual(document.message, "VM is running")
    }

    func testWriteDoesNotOverwriteLifecycleWhenExistingDocumentCannotDecode() throws {
        let harness = try Harness()
        defer { harness.cleanup() }
        try Data("not-json".utf8).write(to: harness.url)

        XCTAssertThrowsError(try harness.store.write(state: .running)) { error in
            guard case RuntimeVMLifecycleStoreError.readFailed = error else {
                return XCTFail("Expected readFailed, got \(error)")
            }
        }
        XCTAssertEqual(try String(contentsOf: harness.url, encoding: .utf8), "not-json")
    }

    func testWriteDoesNotOverwriteLifecycleWhenExistingStartedAtIsInvalid() throws {
        let harness = try Harness()
        defer { harness.cleanup() }
        try harness.writeDocument(RuntimeVMLifecycleDocument(
            state: .starting,
            startedAt: "not-a-date",
            updatedAt: "2026-06-07T00:00:01Z"
        ))

        XCTAssertThrowsError(try harness.store.write(state: .running)) { error in
            XCTAssertEqual(error as? RuntimeVMLifecycleStoreError, .invalidStartedAt("not-a-date"))
        }
        XCTAssertEqual(try harness.readDocument().startedAt, "not-a-date")
    }

    func testLoadPreservesPathInspectionFailure() {
        let url = URL(fileURLWithPath: "/runtime/vm-lifecycle.json")
        let store = RuntimeVMLifecycleStore(
            url: url,
            fileStore: LifecyclePathStateFileStore(pathState: .inspectFailed("permission denied"))
        )

        guard case .failed(let message) = store.load() else {
            return XCTFail("Expected failed load")
        }
        XCTAssertEqual(
            message,
            "VM lifecycle path inspection failed path=/runtime/vm-lifecycle.json reason=permission denied"
        )
    }

    func testLoadPreservesUnexpectedPathState() {
        let url = URL(fileURLWithPath: "/runtime/vm-lifecycle.json")
        let store = RuntimeVMLifecycleStore(
            url: url,
            fileStore: LifecyclePathStateFileStore(pathState: .directory)
        )

        guard case .failed(let message) = store.load() else {
            return XCTFail("Expected failed load")
        }
        XCTAssertEqual(
            message,
            "VM lifecycle path state is unexpected path=/runtime/vm-lifecycle.json state=directory"
        )
    }
}

private final class Harness {
    let directory: URL
    let url: URL
    let store: RuntimeVMLifecycleStore

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        url = directory.appendingPathComponent("vm-lifecycle.json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        store = RuntimeVMLifecycleStore(
            url: url,
            fileStore: SystemRuntimeFileStore(),
            now: { ISO8601DateFormatter().date(from: "2026-06-07T00:01:00Z")! }
        )
    }

    func writeDocument(_ document: RuntimeVMLifecycleDocument) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(document).write(to: url)
    }

    func readDocument() throws -> RuntimeVMLifecycleDocument {
        try JSONDecoder().decode(RuntimeVMLifecycleDocument.self, from: Data(contentsOf: url))
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: directory)
    }
}

private final class LifecyclePathStateFileStore: RuntimeFileReading, RuntimeFileWriting {
    let pathStateValue: RuntimePathState

    init(pathState: RuntimePathState) {
        pathStateValue = pathState
    }

    func fileExists(_ url: URL) -> Bool { false }
    func directoryExists(_ url: URL) -> Bool { false }
    func isExecutableFile(atPath path: String) -> Bool { false }
    func fileState(atPath path: String) -> RuntimeFileState { .missing }
    func fileState(at url: URL) -> RuntimeFileState { .missing }
    func pathState(at url: URL) -> RuntimePathState { pathStateValue }
    func readData(_ url: URL) throws -> Data { Data() }
    func readUTF8Text(_ url: URL) throws -> String { "" }
    func fileSize(_ url: URL) throws -> UInt64 { 0 }
    func modificationDate(_ url: URL) throws -> Date { Date(timeIntervalSince1970: 0) }
    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions) throws {}
    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions, posixPermissions: Int) throws {}
    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {}
    func removeItem(at url: URL) throws {}
    func copyItem(at source: URL, to destination: URL) throws {}
    func moveItem(at source: URL, to destination: URL) throws {}
}
