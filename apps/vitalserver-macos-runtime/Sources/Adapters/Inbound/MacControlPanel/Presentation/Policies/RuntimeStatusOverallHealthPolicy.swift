import RuntimeControl
import Contracts
import Errors

public protocol RuntimeStatusOverallHealthVocabulary {
    var healthyText: String { get }
    var notInstalledText: String { get }
    var installingText: String { get }
    var initializingText: String { get }
    var updatingText: String { get }
    var recoveringText: String { get }
    var needsAttentionText: String { get }
    var criticalText: String { get }
    var unknownText: String { get }

    func runtimeLifecycleText(_ value: String) -> String
    func installStateText(_ state: RuntimeFileState) -> String
}

public enum RuntimeStatusOverallHealthSeverity: Equatable, Sendable {
    case healthy
    case warning
    case critical
    case neutral
}

public struct RuntimeStatusOverallHealthValue: Equatable, Sendable {
    public let text: String
    public let severity: RuntimeStatusOverallHealthSeverity
    public let uptimeText: String?

    public init(
        text: String,
        severity: RuntimeStatusOverallHealthSeverity,
        uptimeText: String?
    ) {
        self.text = text
        self.severity = severity
        self.uptimeText = uptimeText
    }
}

public struct RuntimeStatusOverallHealthPolicy {
    private let vocabulary: any RuntimeStatusOverallHealthVocabulary

    public init(vocabulary: any RuntimeStatusOverallHealthVocabulary) {
        self.vocabulary = vocabulary
    }

    public func overallHealth(
        status: PlatformState,
        operationState: PlatformOperationState
    ) -> RuntimeStatusOverallHealthValue {
        if let operation = operationState.operationForPresentation {
            if RuntimeActiveOperationPolicy.isInstallOperation(operation) {
                return value(vocabulary.installingText, .warning)
            }
            if RuntimeActiveOperationPolicy.isRecoveryInProgress(status, operation: operation) {
                return value(vocabulary.recoveringText, .warning)
            }
            if RuntimeActiveOperationPolicy.isUpdateInProgress(status, operation: operation) {
                return value(vocabulary.updatingText, .warning)
            }
        }
        if status.platformHealth == .initializing {
            return value(vocabulary.initializingText, .warning)
        }
        if RuntimeReadinessPolicy.isReady(status) {
            return value(vocabulary.healthyText, .healthy)
        }
        let installationState = status.runtimeInstallationState
        if installationState == .missing {
            return value(vocabulary.notInstalledText, .critical)
        }
        if !installationState.isExecutable {
            return value(vocabulary.installStateText(installationState), .critical)
        }
        switch status.platformHealth {
        case .some(.installing):
            return value(vocabulary.installingText, .warning)
        case .some(.initializing):
            return value(vocabulary.initializingText, .warning)
        case .some(.updating):
            return value(vocabulary.updatingText, .warning)
        case .some(.recovering):
            return value(vocabulary.recoveringText, .warning)
        case .some(.healthy), .some(.degraded):
            return value(vocabulary.needsAttentionText, .warning)
        case .some(.critical):
            return value(vocabulary.criticalText, .critical)
        case .some(.unknown(let value)):
            return self.value(vocabulary.runtimeLifecycleText(value), .warning)
        default:
            return value(vocabulary.unknownText, .neutral)
        }
    }

    private func value(
        _ text: String,
        _ severity: RuntimeStatusOverallHealthSeverity
    ) -> RuntimeStatusOverallHealthValue {
        RuntimeStatusOverallHealthValue(
            text: text,
            severity: severity,
            uptimeText: nil
        )
    }
}
