import Contracts
import XCTest
import Errors

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
            .present(identifier: "ai.tirosh.vitalserver.helper"),
            .absent(identifier: "ai.tirosh.vitalserver.helper.tools"),
            .readFailed(identifier: "ai.tirosh.vitalserver.helper.tools", reason: "exitCode=1 stderr=denied"),
            .forgetFailed(identifier: "ai.tirosh.vitalserver.helper", reason: "exitCode=1 stderr=locked"),
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
                RuntimeFreshInstallServiceState(label: "ai.tirosh.vitalserver.helper.vm", state: .notLoaded),
            ],
            packageReceiptStates: [.absent(identifier: "ai.tirosh.vitalserver.helper")],
            proxyPortState: .clear(port: 80)
        )

        let encoded = try JSONEncoder().encode(document)
        let decoded = try JSONDecoder().decode(RuntimeFreshInstallPreflightDocument.self, from: encoded)

        XCTAssertEqual(decoded, document)
        XCTAssertFalse(decoded.passed)
        XCTAssertFalse(decoded.blockers.isEmpty)
    }

    func testRuntimeInstallStateDocumentKeepsBlockedProvisionedAndCompletedDistinct() throws {
        let blocked = RuntimeInstallStateDocument(
            state: .preflightBlocked,
            mode: .full,
            currentStep: nil,
            updatedAt: "2026-06-02T00:00:00Z",
            message: "fresh install preflight blocked",
            blockers: ["install-artifact-present:path=/usr/local/bin/vitalserver-vm"]
        )
        let provisioned = RuntimeInstallStateDocument(
            state: .provisioned,
            mode: .provision,
            currentStep: .cleanupInstallSettings,
            updatedAt: "2026-06-02T00:01:00Z",
            message: "runtime install provisioned",
            blockers: []
        )

        let blockedDecoded = try JSONDecoder().decode(
            RuntimeInstallStateDocument.self,
            from: JSONEncoder().encode(blocked)
        )
        let provisionedDecoded = try JSONDecoder().decode(
            RuntimeInstallStateDocument.self,
            from: JSONEncoder().encode(provisioned)
        )

        XCTAssertEqual(blockedDecoded, blocked)
        XCTAssertEqual(provisionedDecoded, provisioned)
        XCTAssertNotEqual(blockedDecoded.state, .completed)
        XCTAssertNotEqual(provisionedDecoded.state, .completed)
        XCTAssertEqual(provisionedDecoded.mode, .provision)
    }

    func testRuntimeInstallModePreservesUnknownValues() throws {
        let mode = RuntimeInstallMode.unknown("future-mode")

        let encoded = try JSONEncoder().encode(mode)
        let decoded = try JSONDecoder().decode(RuntimeInstallMode.self, from: encoded)

        XCTAssertEqual(decoded, mode)
        XCTAssertEqual(decoded.rawValue, "future-mode")
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
