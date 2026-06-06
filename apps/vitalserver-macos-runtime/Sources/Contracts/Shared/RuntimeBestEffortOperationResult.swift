public enum RuntimeBestEffortOperationResult: Equatable, Sendable {
    case completed
    case failed(reason: String)
}
