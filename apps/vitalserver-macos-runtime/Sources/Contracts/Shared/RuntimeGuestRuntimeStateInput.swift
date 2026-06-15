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

public enum RuntimeGuestRuntimeStateInput: Equatable {
    case fresh(vmIP: String?, guestHTTP: RuntimeGuestHTTPStatusInput)
    case missing
    case invalid
    case stale

    public var vmIP: String? {
        guard case .fresh(let vmIP, _) = self else {
            return nil
        }
        return vmIP
    }

    public var guestHTTPStatusText: String {
        guard case .fresh(_, let guestHTTP) = self else {
            return RuntimeHTTPStatusText.missingVMIP
        }
        return guestHTTP.statusText
    }
}
