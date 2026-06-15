import RuntimeControl
import Errors

struct RuntimeSettingsRestartNoticeDecision: Equatable {
    let requiredChanges: [String]
    let message: String

    var requiresRestart: Bool {
        !requiredChanges.isEmpty
    }
}

struct RuntimeSettingsRestartNoticePolicy {
    func decision(
        draft: RuntimeSettings,
        runtime: RuntimeSettings
    ) -> RuntimeSettingsRestartNoticeDecision {
        let changes = requiredRestartChanges(draft: draft, runtime: runtime)
        return RuntimeSettingsRestartNoticeDecision(
            requiredChanges: changes,
            message: message(requiredChanges: changes, restartAfterSave: draft.restartAfterSave)
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

    private func message(requiredChanges: [String], restartAfterSave: Bool) -> String {
        guard !requiredChanges.isEmpty else {
            return AppConstants.StatusText.noVMRuntimeRestartRequired
        }
        let requiredBy = requiredChanges.joined(separator: ", ")
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
