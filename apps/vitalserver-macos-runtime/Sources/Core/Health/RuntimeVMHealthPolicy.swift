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
        if !input.vmExecutable {
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
        if input.vmIP == nil {
            errors.append(.missingIPAddress)
        }
        if !input.guestRuntimeStatePresent {
            errors.append(.runtimeStateMissing)
        }
        if !isSuccessfulHTTPStatus(input.guestHTTP),
           input.guestHTTP != RuntimeHTTPStatusText.missingVMIP {
            errors.append(.guestHTTP(input.guestHTTP))
            if let guestBootstrapFailureReason = input.guestBootstrapFailureReason {
                errors.append(vmError(for: guestBootstrapFailureReason))
            }
        }
        if !input.guestRuntimeStateFresh {
            errors.append(.runtimeStateStale)
        }
        return uniqueErrors(errors + input.reportedVMErrors + (input.vmLifecycle?.reportedVMErrors ?? []))
    }

    private static func vmError(for failureReason: RuntimeFailureReason) -> RuntimeVMError {
        switch failureReason {
        case .guestBootstrapMissingRuntimePackages:
            return .guestBootstrapMissingRuntimePackages
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
            || errors.contains(.guestDiskIO) {
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
        if errors.contains(.runtimeStateStale) {
            return .stale
        }
        if errors.contains(.runtimeStateMissing) {
            return input.vmIP == nil ? .starting : .unreachable
        }
        if errors.contains(.missingIPAddress) {
            return .starting
        }
        if !errors.contains(where: { error in
            if case .guestHTTP = error {
                return true
            }
            return false
        }) {
            return .running
        }
        if input.guestHTTP == RuntimeHTTPStatusText.bootstrapPending
            || input.guestHTTP == RuntimeHTTPStatusText.missingVMIP {
            return .starting
        }
        return .unreachable
    }

    private static func uniqueErrors(_ errors: [RuntimeVMError]) -> [RuntimeVMError] {
        var result: [RuntimeVMError] = []
        for error in errors where !result.contains(error) {
            result.append(error)
        }
        return result
    }
}
