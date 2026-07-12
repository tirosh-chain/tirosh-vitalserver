import Foundation

/// The Guest Runtime Controller rejected a command because its explicit global
/// control lease is owned by another operation.
///
/// This is a public boundary meaning, not a SQLite or HTTP adapter detail.
/// Inbound transports map it to `409 operationInProgress`.
public struct RuntimeControlOperationInProgressError: LocalizedError, Equatable, Sendable {
    public let message: String

    public init(message: String) {
        self.message = message
    }

    public var errorDescription: String? {
        message
    }
}
