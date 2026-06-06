import Contracts
import Workflow
import XCTest

final class RuntimeFreshInstallPreflightRunnerTests: XCTestCase {
    func testRunnerBuildsBlockedDocumentFromExplicitHostStates() {
        let runner = RuntimeFreshInstallPreflightRunner(
            settingsState: {
                .loaded(path: "/private/tmp/tirosh-vitalserver-install.json", proxyPort: 80)
            },
            artifactStates: {
                [.present(path: "/usr/local/bin/vitalserver-vm")]
            },
            serviceStates: {
                RuntimeManagedService.stopOrder.map { service in
                    RuntimeFreshInstallServiceState(
                        label: service.label,
                        state: service == .proxy ? .readFailed("exitCode=1 stderr=denied") : .notLoaded
                    )
                }
            },
            packageReceiptStates: {
                [.absent(identifier: "ai.tirosh.vitalserver.helper")]
            },
            proxyPortState: { port in
                .occupied(port: port, listeners: "nginx/123")
            }
        )

        let document = runner.run()

        XCTAssertFalse(document.passed)
        XCTAssertEqual(document.proxyPort, 80)
        XCTAssertTrue(document.blockers.contains("install-artifact-present:path=/usr/local/bin/vitalserver-vm"))
        XCTAssertTrue(document.blockers.contains("launchd-service-read-failed:label=\(RuntimeManagedService.proxy.label) reason=exitCode=1 stderr=denied"))
        XCTAssertTrue(document.blockers.contains("host-proxy-port-occupied:port=80 listeners=nginx/123"))
    }
}
