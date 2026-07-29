import Contracts

public enum VerifyUpdateBootstrapCompletionReportError:
    Error,
    Equatable,
    Sendable
{
    case completionMissing(journalId: String)
    case reportMissing(path: String)
    case reportInspectionFailed(path: String, reason: String)
    case reportReadFailed(path: String, reason: String)
    case reportPathStateInvalid(path: String, state: String)
    case reportPathMismatch(expected: String, actual: String)
    case reportDigestMismatch(expected: String, actual: String)
}
public struct VerifyUpdateBootstrapCompletionReportUseCase {
    public init() {}

    public func verify(
        settledJournal: UpdateBootstrapJournal,
        reportRead: UpdateBootstrapCompletionReportReadResult
    ) throws {
        guard let completion = settledJournal.completion else {
            throw VerifyUpdateBootstrapCompletionReportError
                .completionMissing(journalId: settledJournal.id)
        }
        let actualPath: String
        let actualSHA256: String
        switch reportRead {
        case .loaded(let path, let sha256):
            actualPath = path
            actualSHA256 = sha256
        case .missing(let path):
            throw VerifyUpdateBootstrapCompletionReportError
                .reportMissing(path: path)
        case .inspectionFailed(let path, let reason):
            throw VerifyUpdateBootstrapCompletionReportError
                .reportInspectionFailed(path: path, reason: reason)
        case .readFailed(let path, let reason):
            throw VerifyUpdateBootstrapCompletionReportError
                .reportReadFailed(path: path, reason: reason)
        case .unexpectedPathState(let path, let state):
            throw VerifyUpdateBootstrapCompletionReportError
                .reportPathStateInvalid(path: path, state: state)
        }
        guard actualPath == completion.reportRelativePath else {
            throw VerifyUpdateBootstrapCompletionReportError
                .reportPathMismatch(
                    expected: completion.reportRelativePath,
                    actual: actualPath
                )
        }
        guard actualSHA256 == completion.reportSHA256 else {
            throw VerifyUpdateBootstrapCompletionReportError
                .reportDigestMismatch(
                    expected: completion.reportSHA256,
                    actual: actualSHA256
                )
        }
    }
}
