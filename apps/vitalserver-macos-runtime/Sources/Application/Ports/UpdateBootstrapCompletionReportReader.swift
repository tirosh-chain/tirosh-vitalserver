import Foundation

public enum UpdateBootstrapCompletionReportReadResult:
    Equatable,
    Sendable
{
    case loaded(path: String, sha256: String)
    case missing(path: String)
    case inspectionFailed(path: String, reason: String)
    case readFailed(path: String, reason: String)
    case unexpectedPathState(path: String, state: String)
}

public protocol UpdateBootstrapCompletionReportReading: Sendable {
    func readCompletionReport(
        relativePath: String,
        beneath stagedRoot: URL
    ) -> UpdateBootstrapCompletionReportReadResult
}

