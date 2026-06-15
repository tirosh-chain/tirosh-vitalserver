import Contracts
import Application
import Domain
import XCTest
import Errors

final class RuntimeFreshInstallPreflightPolicyTests: XCTestCase {
    func testPassedWhenAllHostOwnedStatesAreExplicitlyClear() {
        let document = RuntimeFreshInstallPreflightPolicy.document(input: input())

        XCTAssertTrue(document.passed)
        XCTAssertEqual(document.blockers, [])
        XCTAssertEqual(document.proxyPort, 80)
    }

    func testBlocksPresentArtifactLoadedServiceReceiptAndOccupiedProxyPort() {
        let document = RuntimeFreshInstallPreflightPolicy.document(input: input(
            artifactStates: [
                .present(path: "/Library/Application Support/VitalServerHelper"),
            ],
            serviceStates: freshInstallServiceStates(overrides: [
                RuntimeManagedService.vm.label: .loaded,
            ]),
            packageReceiptStates: [
                .present(identifier: "ai.tirosh.vitalserver.helper"),
            ],
            proxyPortState: .occupied(port: 80, listeners: "nginx/123")
        ))

        XCTAssertFalse(document.passed)
        XCTAssertEqual(document.blockers, [
            "install-artifact-present:path=/Library/Application Support/VitalServerHelper",
            "launchd-service-loaded:label=\(RuntimeManagedService.vm.label)",
            "package-receipt-present:identifier=ai.tirosh.vitalserver.helper",
            "host-proxy-port-occupied:port=80 listeners=nginx/123",
        ])
    }

    func testBlocksReadInvalidAndMissingContractStatesWithoutGuessingAbsence() {
        let document = RuntimeFreshInstallPreflightPolicy.document(input: input(
            settingsState: .invalid(path: "/private/tmp/tirosh-vitalserver-install.json", reason: "proxyPort out of range"),
            artifactStates: [
                .inspectFailed(path: "/usr/local/bin/vitalserver-vm", reason: "permission denied"),
            ],
            serviceStates: freshInstallServiceStates(overrides: [
                RuntimeManagedService.proxy.label: .readFailed("exitCode=1 stderr=permission denied"),
            ]),
            packageReceiptStates: [
                .readFailed(identifier: "ai.tirosh.vitalserver.helper", reason: "exitCode=2 stderr=database locked"),
            ],
            proxyPortState: nil
        ))

        XCTAssertFalse(document.passed)
        XCTAssertEqual(document.blockers, [
            "install-settings-invalid:path=/private/tmp/tirosh-vitalserver-install.json reason=proxyPort out of range",
            "install-artifact-inspect-failed:path=/usr/local/bin/vitalserver-vm reason=permission denied",
            "launchd-service-read-failed:label=\(RuntimeManagedService.proxy.label) reason=exitCode=1 stderr=permission denied",
            "package-receipt-read-failed:identifier=ai.tirosh.vitalserver.helper reason=exitCode=2 stderr=database locked",
        ])
    }

    func testKnownProxyPortRequiresExplicitProxyPortState() {
        let document = RuntimeFreshInstallPreflightPolicy.document(input: input(proxyPortState: nil))

        XCTAssertFalse(document.passed)
        XCTAssertEqual(document.blockers, ["host-proxy-port-state-missing:port=80"])
    }

    func testBlocksMissingSettingsBeforeAnyDefaultIsApplied() {
        let missing = RuntimeFreshInstallPreflightPolicy.document(input: input(
            settingsState: .missing(path: "/private/tmp/tirosh-vitalserver-install.json"),
            proxyPortState: nil
        ))
        let missingProxyPort = RuntimeFreshInstallPreflightPolicy.document(input: input(
            settingsState: .proxyPortMissing(path: "/private/tmp/tirosh-vitalserver-install.json"),
            proxyPortState: nil
        ))

        XCTAssertEqual(missing.blockers, [
            "install-settings-missing:path=/private/tmp/tirosh-vitalserver-install.json",
        ])
        XCTAssertEqual(missingProxyPort.blockers, [
            "install-settings-proxy-port-missing:path=/private/tmp/tirosh-vitalserver-install.json",
        ])
    }

    private func input(
        settingsState: RuntimeInstallSettingsState = .defaulted(path: "/private/tmp/tirosh-vitalserver-install.json", proxyPort: 80),
        artifactStates: [RuntimeInstallArtifactState] = [
            .absent(path: "/Library/Application Support/VitalServerHelper"),
        ],
        serviceStates: [RuntimeFreshInstallServiceState] = freshInstallServiceStates(),
        packageReceiptStates: [RuntimePackageReceiptState] = [
            .absent(identifier: "ai.tirosh.vitalserver.helper"),
        ],
        proxyPortState: RuntimeHostProxyPortState? = .clear(port: 80)
    ) -> RuntimeFreshInstallPreflightInput {
        RuntimeFreshInstallPreflightInput(
            settingsState: settingsState,
            artifactStates: artifactStates,
            serviceStates: serviceStates,
            packageReceiptStates: packageReceiptStates,
            proxyPortState: proxyPortState
        )
    }

}

private func freshInstallServiceStates(
    overrides: [String: RuntimeServiceState] = [:]
) -> [RuntimeFreshInstallServiceState] {
    RuntimeManagedService.stopOrder.map { service in
        RuntimeFreshInstallServiceState(
            label: service.label,
            state: overrides[service.label] ?? .notLoaded
        )
    }
}
