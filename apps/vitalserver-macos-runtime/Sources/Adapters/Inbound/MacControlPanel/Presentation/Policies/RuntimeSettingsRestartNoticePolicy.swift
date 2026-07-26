import RuntimeControl
import Errors

struct RuntimeSettingsRestartNoticeDecision: Equatable {
    let requiredChanges: [String]
    let guestStackChanges: [String]
    let message: String

    var requiresRestart: Bool {
        !requiredChanges.isEmpty
    }

    var requiresGuestStackReconcile: Bool {
        !guestStackChanges.isEmpty
    }

    var requiresActivation: Bool {
        requiresRestart || requiresGuestStackReconcile
    }
}

struct RuntimeSettingsRestartNoticePolicy {
    func decision(
        draft: RuntimeSettings,
        runtime: RuntimeSettings
    ) -> RuntimeSettingsRestartNoticeDecision {
        let changes = requiredRestartChanges(draft: draft, runtime: runtime)
        let guestStackChanges = requiredGuestStackChanges(draft: draft, runtime: runtime)
        return RuntimeSettingsRestartNoticeDecision(
            requiredChanges: changes,
            guestStackChanges: guestStackChanges,
            message: message(
                requiredChanges: changes,
                guestStackChanges: guestStackChanges,
                restartAfterSave: draft.restartAfterSave
            )
        )
    }

    func requiredRestartChanges(
        draft: RuntimeSettings,
        runtime: RuntimeSettings
    ) -> [String] {
        var changes: [String] = []
        appendIfChanged(AppConstants.Labels.cpu, draft.cpuCount, runtime.cpuCount, to: &changes)
        appendIfChanged(AppConstants.Labels.memory, draft.memoryGiB, runtime.memoryGiB, to: &changes)
        appendIfChanged(AppConstants.Labels.disk, draft.diskGiB, runtime.diskGiB, to: &changes)
        appendIfChanged(AppConstants.Labels.mode, draft.networkMode, runtime.networkMode, to: &changes)
        appendIfChanged(AppConstants.Labels.bridgedInterface, draft.bridgedInterface, runtime.bridgedInterface, to: &changes)
        appendIfChanged(
            AppConstants.Labels.vitalFilesDirectory,
            draft.vitalFilesDirectory,
            runtime.vitalFilesDirectory,
            to: &changes
        )
        return changes
    }

    func requiredGuestStackChanges(
        draft: RuntimeSettings,
        runtime: RuntimeSettings
    ) -> [String] {
        var changes: [String] = []
        appendIfChanged(AppConstants.Labels.redisRelay, draft.redisRelay, runtime.redisRelay, to: &changes)
        appendIfChanged(
            AppConstants.Labels.recorderIngressLoadControl,
            draft.recorderIngressSendDataMode,
            runtime.recorderIngressSendDataMode,
            to: &changes
        )
        appendIfChanged(
            AppConstants.Labels.recorderIngressMaxReplayThroughput,
            draft.recorderIngressSendDataReplayMaxMiBPerSecond,
            runtime.recorderIngressSendDataReplayMaxMiBPerSecond,
            to: &changes
        )
        appendIfChanged(
            AppConstants.Labels.recorderIngressHotColdPath,
            draft.recorderIngress,
            runtime.recorderIngress,
            to: &changes
        )
        appendIfChanged(
            AppConstants.Labels.containerMemoryLimits,
            draft.containerMemoryLimitsEnabled,
            runtime.containerMemoryLimitsEnabled,
            to: &changes
        )
        appendIfChanged(
            AppConstants.Labels.vitalServerContainerMemoryLimit,
            draft.vitalServerContainerMemoryLimitMiB,
            runtime.vitalServerContainerMemoryLimitMiB,
            to: &changes
        )
        appendIfChanged(
            AppConstants.Labels.recorderIngressContainerMemoryLimit,
            draft.recorderIngressContainerMemoryLimitMiB,
            runtime.recorderIngressContainerMemoryLimitMiB,
            to: &changes
        )
        appendIfChanged(
            AppConstants.Labels.redisContainerMemoryLimit,
            draft.redisContainerMemoryLimitMiB,
            runtime.redisContainerMemoryLimitMiB,
            to: &changes
        )
        return changes
    }

    private func message(
        requiredChanges: [String],
        guestStackChanges: [String],
        restartAfterSave: Bool
    ) -> String {
        guard !requiredChanges.isEmpty || !guestStackChanges.isEmpty else {
            return AppConstants.StatusText.noRuntimeActivationRequired
        }
        if requiredChanges.isEmpty {
            let requiredBy = guestStackChanges.joined(separator: ", ")
            if restartAfterSave {
                return AppConstants.StatusText.guestStackWillReconcileAfterSave(requiredBy: requiredBy)
            }
            return AppConstants.StatusText.guestStackReconcileRequiredButDisabled(requiredBy: requiredBy)
        }
        let requiredBy = (requiredChanges + guestStackChanges).joined(separator: ", ")
        if restartAfterSave {
            return AppConstants.StatusText.vmRuntimeWillRestartAfterSave(requiredBy: requiredBy)
        }
        return AppConstants.StatusText.vmRuntimeRestartRequiredButDisabled(requiredBy: requiredBy)
    }

    private func appendIfChanged<Value: Equatable>(
        _ label: String,
        _ draft: Value,
        _ runtime: Value,
        to changes: inout [String]
    ) {
        if draft != runtime {
            changes.append(label)
        }
    }
}
