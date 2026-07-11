import Foundation
import MacPlatformAgent
import OutboundAdapters
import RuntimeControl
import XCTest

final class MacPlatformAgentServiceTests: XCTestCase {
    @MainActor
    func testHeadlessServiceOwnsReachableRuntimeControlAPI() async throws {
        let productRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("platform-agent-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: productRoot) }

        let service = MacPlatformAgentService.live(
            installedPaths: InstalledRuntimePaths(productRoot: productRoot),
            servesDevConsole: false,
            port: 0
        )
        try service.start()
        defer { service.stop() }

        let port = try await waitForActivePort(service)
        var request = URLRequest(
            url: try XCTUnwrap(URL(string: "http://127.0.0.1:\(port)/platform/runtime-provider"))
        )
        request.setValue(
            RuntimeControlLocalAPIConstants.token,
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
