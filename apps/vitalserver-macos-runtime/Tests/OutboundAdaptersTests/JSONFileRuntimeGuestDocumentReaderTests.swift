import Application
import Contracts
import OutboundAdapters
import XCTest

final class JSONFileRuntimeGuestDocumentReaderTests: XCTestCase {
    func testLoadsBootstrapResult() throws {
        let harness = try GuestGatewayHarness()
        try harness.writeJSON(
            """
            {
              "schemaVersion": 2,
              "bootID": "boot-1",
              "operation": "bootstrap",
              "status": "failed",
              "message": "Missing runtime packages.",
              "reasonCodes": ["guest-bootstrap-missing-runtime-packages"],
              "updatedAt": "2026-05-21T12:34:57Z"
            }
            """,
            to: harness.bootstrapResultURL
        )

        guard case .loaded(let bootstrapResult) = harness.gateway.loadBootstrapResultDocument() else {
            return XCTFail("Expected loaded bootstrap result")
        }
        XCTAssertEqual(bootstrapResult.status, .failed)
        XCTAssertEqual(bootstrapResult.bootID, "boot-1")
        XCTAssertEqual(bootstrapResult.operation?.rawValue, "bootstrap")
        XCTAssertEqual(bootstrapResult.reasonCodes, [.guestBootstrapMissingRuntimePackages])

        try harness.cleanup()
    }

    func testLoadReportsMissingAndInvalidBootstrapResult() throws {
        let harness = try GuestGatewayHarness()

        guard case .missing = harness.gateway.loadBootstrapResultDocument() else {
            return XCTFail("Expected missing bootstrap result")
        }

        try harness.writeJSON("not-json", to: harness.bootstrapResultURL)
        guard case .failed(let message) = harness.gateway.loadBootstrapResultDocument() else {
            return XCTFail("Expected failed bootstrap result load")
        }
        XCTAssertFalse(message.isEmpty)

        try harness.cleanup()
    }

    func testLoadReportsDirectoryAtBootstrapResultPath() throws {
        let harness = try GuestGatewayHarness()
        try FileManager.default.createDirectory(
            at: harness.bootstrapResultURL,
            withIntermediateDirectories: true
        )
        defer {
            try? harness.cleanup()
        }

        guard case .failed(let message) = harness.gateway.loadBootstrapResultDocument() else {
            return XCTFail("Expected failed bootstrap result load")
        }
        XCTAssertTrue(message.contains("path state is unexpected"))
        XCTAssertTrue(message.contains("state=directory"))
    }

    func testLoadReportsInjectedBootstrapPathInspectionFailure() {
        let urls = GuestGatewayURLs(root: URL(fileURLWithPath: "/guest"))
        let fileStore = GuestGatewayFileStore()
        fileStore.pathStates[urls.bootstrapResult.path] = .inspectFailed("permission denied")
        let gateway = urls.gateway(fileStore: fileStore)

        guard case .failed(let message) = gateway.loadBootstrapResultDocument() else {
            return XCTFail("Expected failed bootstrap result load")
        }
        XCTAssertEqual(
            message,
            "runtime guest document path inspection failed path=\(urls.bootstrapResult.path) reason=permission denied"
        )
    }
}

private struct GuestGatewayURLs {
    let root: URL

    var bootstrapResult: URL { root.appendingPathComponent(RuntimeFileNames.bootstrapResult) }

    func gateway(fileStore: RuntimeFileReading & RuntimeFileWriting) -> JSONFileRuntimeGuestDocumentReader {
        JSONFileRuntimeGuestDocumentReader(
            bootstrapResultURL: bootstrapResult,
            fileStore: fileStore
        )
    }
}

private final class GuestGatewayFileStore: RuntimeFileReading, RuntimeFileWriting {
    var files: [URL: Data] = [:]
    var pathStates: [String: RuntimePathState] = [:]

    func fileExists(_ url: URL) -> Bool {
        files[url] != nil
    }

    func directoryExists(_ url: URL) -> Bool {
        false
    }

    func isExecutableFile(atPath path: String) -> Bool {
        false
    }

    func pathState(at url: URL) -> RuntimePathState {
        if let state = pathStates[url.path] {
            return state
        }
        if files[url] != nil {
            return .file
        }
        return .missing
    }

    func readData(_ url: URL) throws -> Data {
        guard let data = files[url] else {
            throw CocoaError(.fileReadNoSuchFile)
        }
        return data
    }

    func readUTF8Text(_ url: URL) throws -> String {
        String(decoding: try readData(url), as: UTF8.self)
    }

    func fileSize(_ url: URL) throws -> UInt64 {
        UInt64(try readData(url).count)
    }

    func modificationDate(_ url: URL) throws -> Date {
        Date(timeIntervalSince1970: 0)
    }

    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions) throws {
        files[url] = data
        pathStates[url.path] = .file
    }

    func writeData(_ data: Data, to url: URL, options: Data.WritingOptions, posixPermissions: Int) throws {
        try writeData(data, to: url, options: options)
    }

    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {}

    func removeItem(at url: URL) throws {
        files.removeValue(forKey: url)
        pathStates[url.path] = .missing
    }

    func copyItem(at source: URL, to destination: URL) throws {
        files[destination] = try readData(source)
    }

    func moveItem(at source: URL, to destination: URL) throws {
        files[destination] = try readData(source)
        files.removeValue(forKey: source)
    }
}

private struct GuestGatewayHarness {
    let directory: URL
    let bootstrapResultURL: URL
    let gateway: JSONFileRuntimeGuestDocumentReader

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        bootstrapResultURL = directory.appendingPathComponent(RuntimeFileNames.bootstrapResult)
        gateway = JSONFileRuntimeGuestDocumentReader(
            bootstrapResultURL: bootstrapResultURL
        )
    }

    func writeJSON(_ json: String, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(json.utf8).write(to: url)
    }

    func cleanup() throws {
        try FileManager.default.removeItem(at: directory)
    }
}
