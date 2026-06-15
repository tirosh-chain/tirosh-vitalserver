import Contracts

public struct RuntimeGuestRuntimeStateInputAssessment: Equatable {
    public let state: RuntimeGuestRuntimeStateInput
    public let failureReasons: [RuntimeFailureReason]

    public init(
        state: RuntimeGuestRuntimeStateInput,
        failureReasons: [RuntimeFailureReason] = []
    ) {
        self.state = state
        self.failureReasons = failureReasons
    }
}

public enum RuntimeGuestRuntimeStatePolicy {
    public static func inputAssessment(
        freshState: GuestRuntimeStateDocument?,
        loadedState: GuestRuntimeStateDocument?,
        readFailureReasons: [RuntimeFailureReason]
    ) -> RuntimeGuestRuntimeStateInputAssessment {
        if let freshState {
            let guestHTTP = guestHTTPStatus(freshState)
            return RuntimeGuestRuntimeStateInputAssessment(
                state: .fresh(vmIP: nonEmpty(freshState.vmIP), guestHTTP: guestHTTP.status),
                failureReasons: guestHTTP.failureReasons
            )
        }
        if readFailureReasons.contains(where: \.isGuestRuntimeStateReadFailure)
            || readFailureReasons.contains(.guestRuntimeStateInvalid) {
            return RuntimeGuestRuntimeStateInputAssessment(state: .invalid)
        }
        if loadedState != nil {
            return RuntimeGuestRuntimeStateInputAssessment(state: .stale)
        }
        return RuntimeGuestRuntimeStateInputAssessment(state: .missing)
    }

    public static func reportedVMErrors(
        from diskHealth: GuestDiskHealthDocument?
    ) -> [RuntimeVMError] {
        guard let diskHealth else {
            return []
        }
        var errors: [RuntimeVMError] = []
        if diskHealth.rootFilesystemReadOnly == true {
            errors.append(.guestFilesystemReadOnly)
        }
        for line in diskHealth.kernelErrors ?? [] {
            let lowercased = line.lowercased()
            if lowercased.contains("buffer i/o error")
                || lowercased.contains(" i/o error")
                || lowercased.contains("input/output error") {
                errors.append(.guestDiskIO)
            }
            if lowercased.contains("ext4-fs error")
                || lowercased.contains("checksum invalid")
                || lowercased.contains("metadata checksum")
                || lowercased.contains("remounting filesystem read-only") {
                errors.append(.guestFilesystemError)
            }
        }
        return uniqueErrors(errors)
    }

    private static func guestHTTPStatus(_ guestState: GuestRuntimeStateDocument) -> RuntimeGuestHTTPReadResult {
        guard let rawValue = nonEmpty(guestState.guestHTTP) else {
            return RuntimeGuestHTTPReadResult(
                status: .missing,
                failureReasons: [.guestRuntimeStateInvalid]
            )
        }
        if isSuccessfulHTTPStatus(rawValue)
            || rawValue == RuntimeHTTPStatusText.bootstrapPending
            || rawValue == RuntimeHTTPStatusText.missingVMIP {
            return RuntimeGuestHTTPReadResult(status: .reportedStatus(rawValue))
        }
        if Int(rawValue) != nil {
            return RuntimeGuestHTTPReadResult(status: .reportedStatus(rawValue))
        }
        return RuntimeGuestHTTPReadResult(status: .probeFailed(rawValue))
    }

    private static func isSuccessfulHTTPStatus(_ value: String) -> Bool {
        guard let code = Int(value) else {
            return false
        }
        return code >= 200 && code < 300
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else {
            return nil
        }
        return value
    }

    private static func uniqueErrors(_ errors: [RuntimeVMError]) -> [RuntimeVMError] {
        var result: [RuntimeVMError] = []
        for error in errors where !result.contains(error) {
            result.append(error)
        }
        return result
    }
}

private struct RuntimeGuestHTTPReadResult {
    let status: RuntimeGuestHTTPStatusInput
    let failureReasons: [RuntimeFailureReason]

    init(
        status: RuntimeGuestHTTPStatusInput,
        failureReasons: [RuntimeFailureReason] = []
    ) {
        self.status = status
        self.failureReasons = failureReasons
    }
}
