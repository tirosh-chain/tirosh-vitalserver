public enum RecoveryDirective: Equatable, Sendable {
    case retry
    case repair
    case migrate
    case reportOnly
    case notRecoverable
}
