import Contracts
import Interfaces

typealias RuntimeEventDisplayVocabulary = Interfaces.RuntimeEventDisplayVocabulary
typealias RuntimeEventDisplayPolicy = Interfaces.RuntimeEventDisplayPolicy

struct AppRuntimeEventDisplayVocabulary: RuntimeEventDisplayVocabulary {
    var unknownText: String { AppConstants.StatusText.unknown }
    var vmStateLabel: String { AppConstants.Labels.vmState }
    var vmErrorsLabel: String { AppConstants.Labels.vmErrors }
    var failureReasonsLabel: String { AppConstants.Labels.failureReasons }
    var activeRecorderConnectionsLabel: String { AppConstants.Labels.activeRecorderConnections }
    var knownRecordersLabel: String { AppConstants.Labels.knownRecorders }
    var onlineRecordersLabel: String { AppConstants.Labels.onlineRecorders }
    var staleRecordersLabel: String { AppConstants.Labels.staleRecorders }
    var recorderAnomaliesLabel: String { AppConstants.Labels.recorderAnomalies }

    func vmStateText(_ state: RuntimeVMState) -> String {
        AppConstants.StatusText.vmState(state)
    }

    func vmErrorText(_ error: RuntimeVMError) -> String {
        AppConstants.StatusText.vmError(error)
    }

    func domainErrorText(_ reason: RuntimeFailureReason) -> String {
        AppConstants.StatusText.domainError(reason)
    }
}

extension RuntimeEventDisplayPolicy {
    init() {
        self.init(vocabulary: AppRuntimeEventDisplayVocabulary())
    }
}
