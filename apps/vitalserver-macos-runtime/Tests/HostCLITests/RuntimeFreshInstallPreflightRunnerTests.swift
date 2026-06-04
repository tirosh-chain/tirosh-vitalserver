import Contracts
import Core
@testable import HostCLI
import XCTest

final class RuntimeFreshInstallPreflightRunnerTests: XCTestCase {
    func testSettingsReaderReportsMissingSettingsAsDocumentedDefault() {
        let fileStore = RuntimeFileStoreSpy()

        let state = RuntimeInstallSettingsStateReader.state(
            path: "/private/tmp/tirosh-vitalserver-install.json",
            fileStore: fileStore
        )

        XCTAssertEqual(
            state,
            .defaulted(path: "/private/tmp/tirosh-vitalserver-install.json", proxyPort: 80)
        )
    }

    func testSettingsReaderReportsLoadedProxyPort() {
        let fileStore = RuntimeFileStoreSpy()
        let url = URL(fileURLWithPath: "/private/tmp/tirosh-vitalserver-install.json")
        fileStore.files[url] = Data(#"{"proxyPort":8080}"#.utf8)

        let state = RuntimeInstallSettingsStateReader.state(path: url.path, fileStore: fileStore)

        XCTAssertEqual(state, .loaded(path: url.path, proxyPort: 8080))
    }

    func testSettingsReaderReportsInvalidProxyPortWithoutDefaulting() {
        let fileStore = RuntimeFileStoreSpy()
        let url = URL(fileURLWithPath: "/private/tmp/tirosh-vitalserver-install.json")
        fileStore.files[url] = Data(#"{"proxyPort":70000}"#.utf8)

        let state = RuntimeInstallSettingsStateReader.state(path: url.path, fileStore: fileStore)

        XCTAssertEqual(
            state,
            .invalid(path: url.path, reason: "proxyPort out of range value=70000")
        )
    }

    func testSettingsReaderReportsDecodeFailureAsInvalid() {
        let fileStore = RuntimeFileStoreSpy()
        let url = URL(fileURLWithPath: "/private/tmp/tirosh-vitalserver-install.json")
        fileStore.files[url] = Data(#"{"proxyPort":"80"}"#.utf8)

        let state = RuntimeInstallSettingsStateReader.state(path: url.path, fileStore: fileStore)

        guard case .invalid(let path, let reason) = state else {
            return XCTFail("expected invalid settings state, got \(state)")
        }
        XCTAssertEqual(path, url.path)
        XCTAssertFalse(reason.isEmpty)
    }

    func testArtifactReaderDistinguishesAbsentPresentAndInspectFailure() {
        let absent = RuntimeInstallArtifactStateReader.state(
            path: "/missing",
            attributesOfItem: { _ in
                throw CocoaError(.fileReadNoSuchFile)
            }
        )
        let present = RuntimeInstallArtifactStateReader.state(
            path: "/present",
            attributesOfItem: { _ in [:] }
        )
        let failed = RuntimeInstallArtifactStateReader.state(
            path: "/denied",
            attributesOfItem: { _ in
                throw CocoaError(.fileReadNoPermission)
            }
        )

        XCTAssertEqual(absent, .absent(path: "/missing"))
        XCTAssertEqual(present, .present(path: "/present"))
        guard case .inspectFailed(let path, let reason) = failed else {
            return XCTFail("expected inspect failure, got \(failed)")
        }
        XCTAssertEqual(path, "/denied")
        XCTAssertFalse(reason.isEmpty)
    }

    func testProxyPortReaderDistinguishesClearOccupiedAndInspectFailed() {
        let clear = RuntimeHostProxyPortStateReader.state(port: 80) { _, _ in
            RuntimeProcessResult(exitCode: 1, stdout: "", stderr: "")
        }
        let occupied = RuntimeHostProxyPortStateReader.state(port: 80) { _, _ in
            RuntimeProcessResult(
                exitCode: 0,
                stdout: """
                COMMAND PID USER FD TYPE DEVICE SIZE/OFF NODE NAME
                nginx 123 root 6u IPv4 0 0t0 TCP *:80 (LISTEN)
                httpd 456 root 6u IPv4 0 0t0 TCP *:80 (LISTEN)
                """,
                stderr: ""
            )
        }
        let failed = RuntimeHostProxyPortStateReader.state(port: 80) { _, _ in
            RuntimeProcessResult(exitCode: 2, stdout: "", stderr: "permission denied")
        }

        XCTAssertEqual(clear, .clear(port: 80))
        XCTAssertEqual(occupied, .occupied(port: 80, listeners: "httpd/456,nginx/123"))
        XCTAssertEqual(failed, .inspectFailed(port: 80, reason: "exitCode=2 stderr=permission denied"))
    }

}
