import XCTest
import RuntimeControl
@testable import InboundAdapters

final class RuntimeSettingsRestartNoticePolicyTests: XCTestCase {
    private let policy = RuntimeSettingsRestartNoticePolicy()

    func testReportsNoRestartRequiredWhenOnlyNonVMRuntimeSettingsChange() {
        var draft = RuntimeSettings()
        draft.proxyPort = 18080
        draft.vitalServerURL = "https://vitaldb.tirosh.ai/"
        draft.backupRetentionCount = 20

        let decision = policy.decision(draft: draft, runtime: RuntimeSettings())

        XCTAssertFalse(decision.requiresRestart)
        XCTAssertFalse(decision.requiresActivation)
        XCTAssertEqual(decision.requiredChanges, [])
        XCTAssertEqual(decision.message, AppConstants.StatusText.noRuntimeActivationRequired)
    }

    func testReportsRestartRequiredSettingsByDisplayNameWhenRestartIsEnabled() {
        var draft = RuntimeSettings()
        draft.cpuCount = 6
        draft.memoryGiB = 12
        draft.vitalFilesDirectory = "/Volumes/Vital Files"
        draft.restartAfterSave = true

        let decision = policy.decision(draft: draft, runtime: RuntimeSettings())

        XCTAssertTrue(decision.requiresRestart)
        XCTAssertTrue(decision.requiresActivation)
        XCTAssertEqual(decision.requiredChanges, [
            AppConstants.Labels.cpu,
            AppConstants.Labels.memory,
            AppConstants.Labels.vitalFilesDirectory,
        ])
        XCTAssertEqual(
            decision.message,
            "The VM runtime will restart after save. Required by: CPU, Memory allocation, Vital files directory."
        )
    }

    func testWarnsWhenRestartRequiredSettingsChangeButRestartIsDisabled() {
        var draft = RuntimeSettings()
        draft.vitalFilesDirectory = "/Volumes/Vital Files"

        let decision = policy.decision(draft: draft, runtime: RuntimeSettings())

        XCTAssertTrue(decision.requiresRestart)
        XCTAssertEqual(
            decision.message,
            "Saved changes will not become active until the VM runtime restarts. Required by: Vital files directory."
        )
    }

    func testReportsRedisRelayChangeAsContainerServicesReconcileRequired() {
        var draft = RuntimeSettings()
        draft.redisRelay.enabled = true
        draft.restartAfterSave = true

        let decision = policy.decision(draft: draft, runtime: RuntimeSettings())

        XCTAssertFalse(decision.requiresRestart)
        XCTAssertTrue(decision.requiresContainerServicesReconcile)
        XCTAssertTrue(decision.requiresActivation)
        XCTAssertEqual(decision.requiredChanges, [])
        XCTAssertEqual(decision.containerServiceChanges, [AppConstants.Labels.redisRelay])
        XCTAssertEqual(
            decision.message,
            AppConstants.StatusText.containerServicesWillReconcileAfterSave(requiredBy: AppConstants.Labels.redisRelay)
        )
    }

    func testReportsRecorderIngressModeChangeAsContainerServicesReconcileRequired() {
        var draft = RuntimeSettings()
        draft.recorderIngressSendDataMode = .mirrorSpool
        draft.recorderIngressSendDataReplayBatchSize = 8
        draft.recorderIngressSendDataReplayRateLimitPerSecond = 12
        draft.restartAfterSave = true

        let decision = policy.decision(draft: draft, runtime: RuntimeSettings())

        XCTAssertFalse(decision.requiresRestart)
        XCTAssertTrue(decision.requiresContainerServicesReconcile)
        XCTAssertTrue(decision.requiresActivation)
        XCTAssertEqual(decision.requiredChanges, [])
        XCTAssertEqual(decision.containerServiceChanges, [
            AppConstants.Labels.recorderIngressSendDataMode,
            AppConstants.Labels.recorderIngressReplayBatchSize,
            AppConstants.Labels.recorderIngressReplayRateLimit,
        ])
        XCTAssertEqual(
            decision.message,
            AppConstants.StatusText.containerServicesWillReconcileAfterSave(
                requiredBy: [
                    AppConstants.Labels.recorderIngressSendDataMode,
                    AppConstants.Labels.recorderIngressReplayBatchSize,
                    AppConstants.Labels.recorderIngressReplayRateLimit,
                ].joined(separator: ", ")
            )
        )
    }
}
