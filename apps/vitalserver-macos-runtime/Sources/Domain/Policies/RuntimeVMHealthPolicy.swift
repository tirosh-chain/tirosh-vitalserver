import Contracts
import Foundation

public struct RuntimeVMHealthAssessment: Equatable {
    public let vmState: RuntimeVMState
    public let vmErrors: [RuntimeVMError]

    public init(vmState: RuntimeVMState, vmErrors: [RuntimeVMError]) {
        self.vmState = vmState
        self.vmErrors = vmErrors
    }
}

public enum RuntimeVMHealthPolicy {
    public static func evaluate(_ input: RuntimeHealthInput) -> RuntimeVMHealthAssessment {
        let vmErrors = evaluateVMErrors(input)
        return RuntimeVMHealthAssessment(
            vmState: vmState(input, errors: vmErrors),
            vmErrors: vmErrors
        )
    }

    private static func isSuccessfulHTTPStatus(_ value: String) -> Bool {
        guard let code = Int(value) else {
            return false
        }
        return code >= 200 && code < 300
    }

    private static func evaluateVMErrors(_ input: RuntimeHealthInput) -> [RuntimeVMError] {
        var errors: [RuntimeVMError] = []
        if input.vmExecutable != .executable {
            errors.append(.missingExecutable)
        }
        if input.rootfsBase != .present {
            errors.append(.missingRootfsBase)
        }
        if input.vmDisk != .present {
            errors.append(.missingDisk)
        }
        if input.vmService != .loaded {
            errors.append(.serviceNotLoaded(input.vmService.rawValue))
        }
        errors.append(contentsOf: guestReadinessErrors(input.guestReadiness))
        errors.append(contentsOf: guestBootstrapErrors(input))
        return uniqueErrors(
            errors
                + currentHealthVMErrors(input.reportedVMErrors)
                + (input.vmLifecycle?.reportedVMErrors ?? [])
        )
    }

    private static func guestReadinessErrors(_ state: RuntimeGuestReadinessInput) -> [RuntimeVMError] {
        switch state {
        case .notReported:
            return []
        case .reported(let vmIP, let guestHTTP):
            var errors: [RuntimeVMError] = []
            if vmIP == nil {
                errors.append(.missingIPAddress)
            }
            switch guestHTTP {
            case .reportedStatus(let status):
                if !isSuccessfulHTTPStatus(status) {
                    errors.append(.guestHTTP(status))
                }
            case .missing:
                errors.append(.guestHTTP(RuntimeHTTPStatusText.missingGuestHTTP))
            case .probeFailed(let status):
                errors.append(.guestHTTPProbeFailed(status))
            }
            return errors
        }
    }

    private static func guestBootstrapErrors(_ input: RuntimeHealthInput) -> [RuntimeVMError] {
        if case .failed(let reason) = input.guestBootstrapAssessment {
            return [vmError(for: reason)]
        }
        guard case .reported(_, let guestHTTP) = input.guestReadiness,
              !guestHTTP.isSuccessful else {
            return []
        }
        switch input.guestBootstrapAssessment {
        case .missing:
            return isBootstrapping(input.vmLifecycle) ? [] : [.guestBootstrapResultMissing]
        case .unavailable:
            return [.guestBootstrapResultUnavailable]
        case .notCurrentBoot, .noFailure, .failed:
            return []
        }
    }

    private static func isBootstrapping(_ lifecycle: RuntimeVMLifecycleDocument?) -> Bool {
        lifecycle?.state == .starting || lifecycle?.state == .bootstrapping
    }

    private static func vmError(for failureReason: RuntimeFailureReason) -> RuntimeVMError {
        switch failureReason {
        case .guestBootstrapMissingRuntimePackages:
            return .guestBootstrapMissingRuntimePackages
        case .guestBootstrapDockerRuntimeFailed:
            return .guestBootstrapDockerRuntimeFailed
        case .guestBootstrapFailed:
            return .guestBootstrapFailed
        default:
            return .unknown(failureReason.rawValue)
        }
    }

    private static func vmState(_ input: RuntimeHealthInput, errors: [RuntimeVMError]) -> RuntimeVMState {
        if errors.contains(.missingExecutable) {
            return .notInstalled
        }
        if errors.contains(.missingRootfsBase)
            || errors.contains(.missingDisk)
            || errors.contains(where: { error in
                if case .launchFailed = error {
                    return true
                }
                return false
            })
            || errors.contains(.diskAttachmentInvalid)
            || errors.contains(.guestFilesystemError)
            || errors.contains(.guestFilesystemReadOnly)
            || errors.contains(.guestDiskIO)
            || errors.contains(.guestBootstrapMissingRuntimePackages)
            || errors.contains(.guestBootstrapDockerRuntimeFailed)
            || errors.contains(.guestBootstrapFailed) {
            return .failed
        }
        if errors.contains(where: { error in
            if case .serviceNotLoaded = error {
                return true
            }
            return false
        }) {
            return .stopped
        }
        if input.vmLifecycle?.state == .stopping {
            return .stopped
        }
        if input.vmLifecycle?.state == .starting || input.vmLifecycle?.state == .bootstrapping {
            return .starting
        }
        if errors.contains(.missingIPAddress) {
            return .starting
        }
        if !errors.contains(where: isGuestHTTPError) {
            return .running
        }
        let guestHTTP = input.guestReadiness.guestHTTPStatusText
        if guestHTTP == RuntimeHTTPStatusText.bootstrapPending
            || guestHTTP == RuntimeHTTPStatusText.missingVMIP {
            return .starting
        }
        return .unreachable
    }

    private static func isGuestHTTPError(_ error: RuntimeVMError) -> Bool {
        switch error {
        case .guestHTTP, .guestHTTPProbeFailed:
            return true
        default:
            return false
        }
    }

    private static func currentHealthVMErrors(_ errors: [RuntimeVMError]) -> [RuntimeVMError] {
        errors.filter { error in
            switch error {
            case .runtimeStateMissing, .runtimeStateInvalid, .runtimeStateStale:
                return false
            default:
                return true
            }
        }
    }

    private static func uniqueErrors(_ errors: [RuntimeVMError]) -> [RuntimeVMError] {
        var result: [RuntimeVMError] = []
        for error in errors where !result.contains(error) {
            result.append(error)
        }
        return result
    }
}
