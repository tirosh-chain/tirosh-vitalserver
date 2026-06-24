import RuntimeControl
import Errors

struct RuntimeSettingsRestartNoticeDecision: Equatable {
    let requiredChanges: [String]
    let containerServiceChanges: [String]
    let message: String

    var requiresRestart: Bool {
        !requiredChanges.isEmpty
    }

    var requiresContainerServicesReconcile: Bool {
        !containerServiceChanges.isEmpty
    }

    var requiresActivation: Bool {
        requiresRestart || requiresContainerServicesReconcile
    }
}

struct RuntimeSettingsRestartNoticePolicy {
    func decision(
        draft: RuntimeSettings,
        runtime: RuntimeSettings
    ) -> RuntimeSettingsRestartNoticeDecision {
        let changes = requiredRestartChanges(draft: draft, runtime: runtime)
        let containerServiceChanges = requiredContainerServiceChanges(draft: draft, runtime: runtime)
        return RuntimeSettingsRestartNoticeDecision(
            requiredChanges: changes,
            containerServiceChanges: containerServiceChanges,
            message: message(
                requiredChanges: changes,
                containerServiceChanges: containerServiceChanges,
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

    func requiredContainerServiceChanges(
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
        containerServiceChanges: [String],
        restartAfterSave: Bool
    ) -> String {
        guard !requiredChanges.isEmpty || !containerServiceChanges.isEmpty else {
            return AppConstants.StatusText.noRuntimeActivationRequired
        }
        if requiredChanges.isEmpty {
            let requiredBy = containerServiceChanges.joined(separator: ", ")
            if restartAfterSave {
                return AppConstants.StatusText.containerServicesWillReconcileAfterSave(requiredBy: requiredBy)
            }
            return AppConstants.StatusText.containerServicesReconcileRequiredButDisabled(requiredBy: requiredBy)
        }
        let requiredBy = (requiredChanges + containerServiceChanges).joined(separator: ", ")
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
