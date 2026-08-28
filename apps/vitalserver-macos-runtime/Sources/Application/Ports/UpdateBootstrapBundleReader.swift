import Contracts

public enum UpdateBootstrapEnvelopeReadResult: Equatable, Sendable {
    case missing(path: String)
    case unexpectedPathState(path: String, state: String)
    case inspectionFailed(path: String, reason: String)
    case readFailed(path: String, reason: String)
    case decodeFailed(path: String, reason: String)
    case loaded(UpdateBootstrapEnvelope)
}

public enum UpdateBootstrapBundleEntriesReadResult: Equatable, Sendable {
    case rootMissing(path: String)
    case unexpectedRootPathState(path: String, state: String)
    case rootInspectionFailed(path: String, reason: String)
    case listingFailed(path: String, reason: String)
    case loaded([UpdateBootstrapBundleEntry])
}

public protocol UpdateBootstrapEnvelopeReading: Sendable {
    func readEnvelope() -> UpdateBootstrapEnvelopeReadResult
}

public protocol UpdateBootstrapBundleEntriesReading: Sendable {
    func readEntries() -> UpdateBootstrapBundleEntriesReadResult
}
