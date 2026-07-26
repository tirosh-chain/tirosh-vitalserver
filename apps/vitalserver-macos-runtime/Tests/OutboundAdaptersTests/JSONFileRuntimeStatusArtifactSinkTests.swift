import Application
import Contracts
import Domain
import OutboundAdapters
import XCTest
import Errors

final class JSONFileRuntimeStatusArtifactSinkTests: XCTestCase {
    func testSaveRuntimeStatusDocument() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let url = directory.appendingPathComponent(RuntimeDiagnosticsArtifactFileNames.runtimeStatus)
        let sink = JSONFileRuntimeStatusArtifactSink(url: url)

        try sink.save(document())

        let loaded = try JSONDecoder().decode(
            RuntimeStatusDocument.self,
            from: Data(contentsOf: url)
        )
        XCTAssertEqual(loaded.schemaVersion, 2)
        XCTAssertEqual(loaded.status, .healthy)
        XCTAssertEqual(loaded.runtimeVersion, "0.1.4")

        try? FileManager.default.removeItem(at: directory)
    }

    func testSaveUsesInjectedFileStore() throws {
        let url = URL(fileURLWithPath: "/runtime/status.json")
        let fileStore = StatusArtifactSinkFileStore()
        let sink = JSONFileRuntimeStatusArtifactSink(url: url, fileStore: fileStore)

        try sink.save(document())

        XCTAssertEqual(fileStore.createdDirectories, [url.deletingLastPathComponent()])
        let loaded = try JSONDecoder().decode(
            RuntimeStatusDocument.self,
            from: try fileStore.readData(url)
        )
        XCTAssertEqual(loaded.runtimeVersion, "0.1.4")
    }

    func testSaveAllowsStatusDirectoryCreationWhenRequiredRootExists() throws {
        let root = URL(fileURLWithPath: "/runtime")
        let url = root.appendingPathComponent("status").appendingPathComponent(RuntimeDiagnosticsArtifactFileNames.runtimeStatus)
        let fileStore = StatusArtifactSinkFileStore()
        fileStore.pathStates[root.path] = .directory
        let sink = JSONFileRuntimeStatusArtifactSink(
            url: url,
            requiredExistingRoot: root,
            fileStore: fileStore
        )

        try sink.save(document())

        XCTAssertEqual(fileStore.createdDirectories, [url.deletingLastPathComponent()])
        XCTAssertEqual(fileStore.pathState(at: url), .file)
    }

    func testSaveDoesNotCreateRuntimeStatusWhenRequiredRootIsMissing() {
        let root = URL(fileURLWithPath: "/runtime")
        let url = root.appendingPathComponent("status").appendingPathComponent(RuntimeDiagnosticsArtifactFileNames.runtimeStatus)
        let fileStore = StatusArtifactSinkFileStore()
        let sink = JSONFileRuntimeStatusArtifactSink(
            url: url,
            requiredExistingRoot: root,
            fileStore: fileStore
        )

        XCTAssertThrowsError(try sink.save(document())) { error in
            XCTAssertEqual(error as? RuntimeArtifactSinkError, .missingRequiredRoot(path: root.path))
        }
        XCTAssertEqual(fileStore.createdDirectories, [])
        XCTAssertEqual(fileStore.pathState(at: url), .missing)
    }

    private func document() -> RuntimeStatusDocument {
        RuntimeStatusDocument(
            schemaVersion: 2,
            product: "VitalServerHelper",
            status: .healthy,
            productRoot: "/Library/Application Support/VitalServerHelper",
            runtimeHome: "/Library/Application Support/VitalServerHelper/vm",
            runtimeVersion: "0.1.4",
            vmService: .loaded,
            proxyService: .loaded,
            watchdogService: .loaded,
            vmIP: "192.168.64.2",
            proxyPort: 80,
            hostProxyHTTP: "200",
            guestHTTP: "200",
            redisUIHTTP: "200",
            swaggerUIHTTP: "200",
            rootfsBase: .present,
            vmDisk: .present,
            latestBackup: nil
        )
    }
}

private final class StatusArtifactSinkFileStore: RuntimeFileReading, RuntimeFileWriting {
    var files: [URL: Data] = [:]
    var pathStates: [String: RuntimePathState] = [:]
    var createdDirectories: [URL] = []

    func fileExists(_ url: URL) -> Bool {
        files[url] != nil
    }

    func directoryExists(_ url: URL) -> Bool {
        createdDirectories.contains(url)
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

    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        createdDirectories.append(url)
    }

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
