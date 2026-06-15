public enum RuntimeObservationInput<Observation: Equatable & Sendable>: Equatable, Sendable {
    case notReported
    case missing
    case readFailed(String)
    case loaded(Observation)

    public var observedValue: Observation? {
        guard case .loaded(let value) = self else {
            return nil
        }
        return value
    }
}
