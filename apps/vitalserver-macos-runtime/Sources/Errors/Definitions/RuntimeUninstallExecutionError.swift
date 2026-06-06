public struct RuntimeUninstallFileRemovalExecutionError: Error {
    public let underlyingError: Error
    public let blockers: [String]

    public init(underlyingError: Error, blockers: [String]) {
        self.underlyingError = underlyingError
        self.blockers = blockers
    }
}

public struct RuntimeUninstallReceiptForgetExecutionError: Error, Equatable {
    public let identifier: String
    public let reason: String

    public init(identifier: String, reason: String) {
        self.identifier = identifier
        self.reason = reason
    }
}
