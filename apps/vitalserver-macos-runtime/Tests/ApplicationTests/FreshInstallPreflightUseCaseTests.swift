import Application
import Contracts
import Domain
import XCTest

final class FreshInstallPreflightUseCaseTests: XCTestCase {
    func testRunBuildsBlockedDocumentFromExplicitHostStates() {
        let operations = FreshInstallPreflightOperations(
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

        let document = FreshInstallPreflightUseCase().run(operations: operations)

        XCTAssertFalse(document.passed)
        XCTAssertEqual(document.proxyPort, 80)
        XCTAssertTrue(document.blockers.contains("install-artifact-present:path=/usr/local/bin/vitalserver-vm"))
        XCTAssertTrue(document.blockers.contains("launchd-service-read-failed:label=\(RuntimeManagedService.proxy.label) reason=exitCode=1 stderr=denied"))
        XCTAssertTrue(document.blockers.contains("host-proxy-port-occupied:port=80 listeners=nginx/123"))
    }

    func testRunDoesNotProbeProxyPortWhenSettingsStateHasNoPort() {
        let operations = FreshInstallPreflightOperations(
            settingsState: {
                .readFailed(path: "/private/tmp/tirosh-vitalserver-install.json", reason: "permission denied")
            },
            artifactStates: {
                [.absent(path: "/usr/local/bin/vitalserver-vm")]
            },
            serviceStates: {
                RuntimeManagedService.stopOrder.map {
                    RuntimeFreshInstallServiceState(label: $0.label, state: .notLoaded)
                }
            },
            packageReceiptStates: {
                [.absent(identifier: "ai.tirosh.vitalserver.helper")]
            },
            proxyPortState: { _ in
                XCTFail("proxy port must not be read when settings do not provide an explicit port")
                return .inspectFailed(port: 0, reason: "unexpected")
            }
        )

        let document = FreshInstallPreflightUseCase().run(operations: operations)

        XCTAssertFalse(document.passed)
        XCTAssertEqual(document.proxyPort, nil)
        XCTAssertEqual(document.proxyPortState, nil)
        XCTAssertEqual(
            document.blockers,
            ["install-settings-read-failed:path=/private/tmp/tirosh-vitalserver-install.json reason=permission denied"]
        )
    }
}
