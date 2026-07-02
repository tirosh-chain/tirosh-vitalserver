public enum RuntimeGuestHTTPStatusInput: Equatable {
    case reportedStatus(String)
    case missing
    case probeFailed(String)

    public var statusText: String {
        switch self {
        case .reportedStatus(let value):
            return value
        case .missing:
            return RuntimeHTTPStatusText.missingGuestHTTP
        case .probeFailed(let value):
            return value
        }
    }

    public var isSuccessful: Bool {
        guard case .reportedStatus(let value) = self,
              let code = Int(value) else {
            return false
        }
        return code >= 200 && code < 300
    }
}

public enum RuntimeGuestReadinessInput: Equatable {
    case notReported
    case reported(vmIP: String?, guestHTTP: RuntimeGuestHTTPStatusInput)

    public var vmIP: String? {
        guard case .reported(let vmIP, _) = self else {
            return nil
        }
        return vmIP
    }

    public var guestHTTPStatusText: String {
        switch self {
        case .notReported:
            return RuntimeHTTPStatusText.notRead
        case .reported(_, let guestHTTP):
            return guestHTTP.statusText
        }
    }
}
