import Foundation
@testable import OutboundAdapters
import RuntimeControl
import XCTest

final class RuntimeControlAPIAutomationCredentialsTests: XCTestCase {
    func testTokenStoreCreatesRootOwnedAutomationTokenAndReloadsIt() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("runtime-control-token-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let tokenURL = root
            .appendingPathComponent("secrets", isDirectory: true)
            .appendingPathComponent("platform-api-token")
        let store = RuntimeControlAPIAutomationTokenStore(tokenURL: tokenURL)

        let created = try store.loadOrCreate()

        XCTAssertFalse(created.isEmpty)
        XCTAssertEqual(try store.load(), created)
        let permissions = try XCTUnwrap(
            FileManager.default.attributesOfItem(atPath: tokenURL.path)[.posixPermissions] as? NSNumber
        )
        XCTAssertEqual(permissions.intValue & 0o777, 0o600)
    }

    func testTokenStoreDoesNotTreatMissingOrEmptyTokenAsCredentials() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("runtime-control-token-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let tokenURL = root.appendingPathComponent("platform-api-token")
        let store = RuntimeControlAPIAutomationTokenStore(tokenURL: tokenURL)

        XCTAssertThrowsError(try store.load()) { error in
            guard case .tokenMissing = error as? RuntimeControlAPIAutomationCredentialsError else {
                return XCTFail("expected missing token error, got \(error)")
            }
        }

        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data("\n".utf8).write(to: tokenURL)
        XCTAssertThrowsError(try store.load()) { error in
            guard case .tokenInvalid = error as? RuntimeControlAPIAutomationCredentialsError else {
                return XCTFail("expected invalid token error, got \(error)")
            }
        }
    }

    func testEndpointReadsConfiguredRootOwnedPort() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("runtime-control-endpoint-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let settingsURL = root.appendingPathComponent("runtime-control-settings.json")
        try JSONEncoder().encode(RuntimeControlSettingsDocument(
            runtimeControlPort: 18444
        )).write(to: settingsURL)

        XCTAssertEqual(
            try RuntimeControlAPIAutomationEndpoint(settingsURL: settingsURL).baseURL(),
            "http://127.0.0.1:18444/"
        )
    }
}
