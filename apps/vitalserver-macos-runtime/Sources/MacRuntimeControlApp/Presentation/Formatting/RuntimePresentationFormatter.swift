import Contracts
import Interfaces

typealias RuntimePresentationFormatter = Interfaces.RuntimePresentationFormatter
typealias RuntimePresentationVocabulary = Interfaces.RuntimePresentationVocabulary

private struct AppRuntimePresentationVocabulary: RuntimePresentationVocabulary {
    var advertisedURLSameHostLabel: String { AppConstants.Labels.advertisedURLSameHost }
    var unknownText: String { AppConstants.StatusText.unknown }
    var updateBundleConfirmationText: String { AppConstants.StatusText.updateBundleConfirmation }
    var applySettingsConfirmationText: String { AppConstants.StatusText.applySettingsConfirmation }
    var failureReasonsLabel: String { AppConstants.Labels.failureReasons }
    var updateBundleApplyingText: String { AppConstants.StatusText.updateBundleApplying }
    var trueText: String { AppConstants.Values.boolTrue }
    var falseText: String { AppConstants.Values.boolFalse }
    var preventSystemSleepLabel: String { AppConstants.Labels.preventSystemSleep }

    func vitalServerURL(proxyPort: Int) -> String {
        AppConstants.Product.vitalServerURL(proxyPort: proxyPort)
    }

    func remoteConsoleURL(port: Int) -> String {
        AppConstants.Product.remoteConsoleURL(port: port)
    }

    func domainErrorText(_ reason: RuntimeFailureReason) -> String {
        AppConstants.StatusText.domainError(reason)
    }

    func runtimeLifecycleText(_ rawValue: String?) -> String {
        AppConstants.StatusText.runtimeLifecycle(rawValue)
    }

    func operationText(_ rawValue: String?) -> String {
        AppConstants.StatusText.operation(rawValue)
    }

    func progressStepStatusText(_ rawValue: String) -> String {
        AppConstants.StatusText.progressStepStatus(rawValue)
    }
}

extension RuntimePresentationFormatter {
    init() {
        self.init(vocabulary: AppRuntimePresentationVocabulary())
    }
}
