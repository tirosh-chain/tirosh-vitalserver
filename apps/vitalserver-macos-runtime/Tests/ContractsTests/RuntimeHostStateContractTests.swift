import Contracts
import XCTest

final class RuntimeHostStateContractTests: XCTestCase {
    func testRuntimeServiceStateKeepsReadFailureDistinctFromNotLoaded() throws {
        let state = RuntimeServiceState.readFailed("exitCode=1 stderr=permission denied")

        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(RuntimeServiceState.self, from: encoded)

        XCTAssertEqual(decoded, state)
        XCTAssertFalse(decoded.isLoaded)
        XCTAssertTrue(decoded.isReadFailure)
        XCTAssertNotEqual(decoded, .notLoaded)
    }

    func testRuntimeVMProcessStateEncodesBlockingState() throws {
        let state = RuntimeVMProcessState.stopTimedOut(pid: 123, timeoutSeconds: 900)

        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(RuntimeVMProcessState.self, from: encoded)

        XCTAssertEqual(decoded, state)
        XCTAssertTrue(decoded.blocksUninstallCleanup)
    }

    func testRuntimeVMProcessStateKeepsMissingPidFileBlocking() throws {
        let state = RuntimeVMProcessState.pidFileMissing

        let encoded = try JSONEncoder().encode(state)
        let decoded = try JSONDecoder().decode(RuntimeVMProcessState.self, from: encoded)

        XCTAssertEqual(decoded, state)
        XCTAssertTrue(decoded.blocksUninstallCleanup)
        XCTAssertNotEqual(decoded, RuntimeVMProcessState.stopped)
    }

    func testRuntimePackageReceiptStateKeepsPresentAndReadFailureDistinctFromAbsent() throws {
        let states: [RuntimePackageReceiptState] = [
            .present(identifier: "com.tirosh.vitalserver.vm"),
            .absent(identifier: "com.tirosh.vitalserver"),
            .readFailed(identifier: "com.tirosh.vitalserver.tools", reason: "exitCode=1 stderr=denied"),
            .forgetFailed(identifier: "com.tirosh.vitalserver.vm", reason: "exitCode=1 stderr=locked"),
        ]

        let encoded = try JSONEncoder().encode(states)
        let decoded = try JSONDecoder().decode([RuntimePackageReceiptState].self, from: encoded)

        XCTAssertEqual(decoded, states)
        XCTAssertTrue(decoded[0].blocksUninstallCompletion)
        XCTAssertFalse(decoded[1].blocksUninstallCompletion)
        XCTAssertTrue(decoded[2].blocksUninstallCompletion)
        XCTAssertTrue(decoded[3].blocksUninstallCompletion)
    }

    func testRuntimeFreshInstallStatesKeepFailedAndBlockingStatesDistinct() throws {
        let settingsStates: [RuntimeInstallSettingsState] = [
            .defaulted(path: "/private/tmp/tirosh-vitalserver-install.json", proxyPort: 80),
            .loaded(path: "/private/tmp/tirosh-vitalserver-install.json", proxyPort: 8080),
            .readFailed(path: "/private/tmp/tirosh-vitalserver-install.json", reason: "permission denied"),
            .invalid(path: "/private/tmp/tirosh-vitalserver-install.json", reason: "proxyPort out of range"),
        ]
        let artifactStates: [RuntimeInstallArtifactState] = [
            .absent(path: "/usr/local/bin/vitalserver-vm"),
            .present(path: "/usr/local/bin/vitalserver-vm"),
            .inspectFailed(path: "/usr/local/bin/vitalserver-vm", reason: "permission denied"),
        ]
        let proxyPortStates: [RuntimeHostProxyPortState] = [
            .clear(port: 80),
            .occupied(port: 80, listeners: "nginx/123"),
            .inspectFailed(port: 80, reason: "lsof unavailable"),
        ]

        let settingsDecoded = try JSONDecoder().decode(
            [RuntimeInstallSettingsState].self,
            from: JSONEncoder().encode(settingsStates)
        )
        let artifactDecoded = try JSONDecoder().decode(
            [RuntimeInstallArtifactState].self,
            from: JSONEncoder().encode(artifactStates)
        )
        let proxyPortDecoded = try JSONDecoder().decode(
            [RuntimeHostProxyPortState].self,
            from: JSONEncoder().encode(proxyPortStates)
        )

        XCTAssertEqual(settingsDecoded, settingsStates)
        XCTAssertFalse(settingsDecoded[0].blocksFreshInstall)
        XCTAssertFalse(settingsDecoded[1].blocksFreshInstall)
        XCTAssertTrue(settingsDecoded[2].blocksFreshInstall)
        XCTAssertTrue(settingsDecoded[3].blocksFreshInstall)
        XCTAssertEqual(artifactDecoded, artifactStates)
        XCTAssertFalse(artifactDecoded[0].blocksFreshInstall)
        XCTAssertTrue(artifactDecoded[1].blocksFreshInstall)
        XCTAssertTrue(artifactDecoded[2].blocksFreshInstall)
        XCTAssertEqual(proxyPortDecoded, proxyPortStates)
        XCTAssertFalse(proxyPortDecoded[0].blocksFreshInstall)
        XCTAssertTrue(proxyPortDecoded[1].blocksFreshInstall)
        XCTAssertTrue(proxyPortDecoded[2].blocksFreshInstall)
    }

    func testRuntimeFreshInstallPreflightDocumentKeepsBlockedDistinctFromPassed() throws {
        let document = RuntimeFreshInstallPreflightDocument(
            passed: false,
            proxyPort: 80,
            blockers: ["install-artifact-present:path=/usr/local/bin/vitalserver-vm"],
            settingsState: .defaulted(path: "/private/tmp/tirosh-vitalserver-install.json", proxyPort: 80),
            artifactStates: [.present(path: "/usr/local/bin/vitalserver-vm")],
            serviceStates: [
                RuntimeFreshInstallServiceState(label: "com.tirosh.vitalserver-vm", state: .notLoaded),
            ],
            packageReceiptStates: [.absent(identifier: "com.tirosh.vitalserver.vm")],
            proxyPortState: .clear(port: 80)
        )

        let encoded = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(RuntimeFreshInstallPreflightDocument.self, from: encoded)

        XCTAssertEqual(decoded, document)
        XCTAssertFalse(decoded.passed)
        XCTAssertFalse(decoded.blockers.isEmpty)
    }

    func testRuntimeUninstallStateDocumentKeepsBlockedDistinctFromCompleted() throws {
        let document = RuntimeUninstallStateDocument(
            state: .serviceStopBlocked,
            clean: true,
            updatedAt: "2026-06-02T00:00:00Z",
            message: "service stop blocked",
            blockers: ["vm-process-running:pid=123"]
        )

        let encoded = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(RuntimeUninstallStateDocument.self, from: encoded)

        XCTAssertEqual(decoded, document)
        XCTAssertNotEqual(decoded.state, .completed)
    }
}
