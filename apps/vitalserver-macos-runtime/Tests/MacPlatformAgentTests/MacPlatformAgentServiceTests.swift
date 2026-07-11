import Foundation
@testable import MacPlatformAgent
import OutboundAdapters
import RuntimeControl
import XCTest

final class MacPlatformAgentServiceTests: XCTestCase {
    @MainActor
    func testHeadlessServiceOwnsReachableRuntimeControlAPI() async throws {
        let productRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("platform-agent-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: productRoot) }

        let service = try MacPlatformAgentService.live(
            installedPaths: InstalledRuntimePaths(productRoot: productRoot),
            servesDevConsole: false,
            port: 0,
            automationToken: "test-token"
        )
        try service.start()
        defer { service.stop() }

        let port = try await waitForActivePort(service)
        var request = URLRequest(
            url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/platform/runtime-provider"))
        )
        request.setValue(
            "test-token",
            forHTTPHeaderField: "X-Runtime-Control-Token"
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        let httpResponse = try XCTUnwrap(response as? HTTPURLResponse)
        let runtimeProvider = try JSONDecoder().decode(RuntimeVMLifecycleResourceState.self, from: data)

        XCTAssertEqual(httpResponse.statusCode, 200)
        XCTAssertEqual(runtimeProvider.state, .missing)
        XCTAssertNil(runtimeProvider.document)
        XCTAssertTrue(runtimeProvider.readError?.contains("vm-lifecycle.json") == true)
    }

    @MainActor
    func testLocalAPISettingsReaderReadsConfiguredPortFromRootOwnedDocument() throws {
        let productRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("platform-agent-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: productRoot) }
        try FileManager.default.createDirectory(at: productRoot, withIntermediateDirectories: true)
        let paths = InstalledRuntimePaths(productRoot: productRoot)
        let configuredPort = 18444
        try JSONEncoder().encode(RuntimeControlSettingsDocument(
            runtimeControlPort: configuredPort
        )).write(to: paths.runtimeControlSettings)

        let reader = RuntimeControlLocalAPISettingsReader(documentURL: paths.runtimeControlSettings)
        XCTAssertEqual(try reader.loadPort(), configuredPort)
    }

    @MainActor
    func testLocalAPISettingsReaderRejectsInvalidConfiguredPort() throws {
        let productRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("platform-agent-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: productRoot) }
        try FileManager.default.createDirectory(at: productRoot, withIntermediateDirectories: true)
        let paths = InstalledRuntimePaths(productRoot: productRoot)
        try JSONEncoder().encode(RuntimeControlSettingsDocument(
            runtimeControlPort: 65_536
        )).write(to: paths.runtimeControlSettings)

        let reader = RuntimeControlLocalAPISettingsReader(documentURL: paths.runtimeControlSettings)
        XCTAssertThrowsError(try reader.loadPort()) { error in
            guard case let .invalidPort(path, port) = error as? RuntimeControlLocalAPISettingsError else {
                return XCTFail("expected invalid Runtime Control API port error, got \(error)")
            }
            XCTAssertEqual(path, paths.runtimeControlSettings.path)
            XCTAssertEqual(port, 65_536)
        }
    }

    @MainActor
    private func waitForActivePort(
        _ service: MacPlatformAgentService
    ) async throws -> UInt16 {
        for _ in 0..<100 {
            if let port = service.activePort {
                return port
            }
            try await Task.sleep(for: .milliseconds(20))
        }
        XCTFail("Platform Agent listener did not become ready")
        throw PlatformAgentTestError.listenerNotReady
    }
}

private enum PlatformAgentTestError: Error {
    case listenerNotReady
}
