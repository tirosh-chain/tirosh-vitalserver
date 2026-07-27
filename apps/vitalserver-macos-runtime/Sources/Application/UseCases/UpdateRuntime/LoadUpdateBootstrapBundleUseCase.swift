import Contracts
import Domain

public enum LoadUpdateBootstrapBundleError: Error, Equatable, Sendable {
    case envelopeMissing(path: String)
    case envelopeUnexpectedPathState(path: String, state: String)
    case envelopeInspectionFailed(path: String, reason: String)
    case envelopeReadFailed(path: String, reason: String)
    case envelopeDecodeFailed(path: String, reason: String)
    case bundleRootMissing(path: String)
    case bundleRootUnexpectedPathState(path: String, state: String)
    case bundleRootInspectionFailed(path: String, reason: String)
    case bundleListingFailed(path: String, reason: String)
    case closureInvalid(UpdateBootstrapBundleClosureError)
}

public struct LoadUpdateBootstrapBundleUseCase {
    public init() {}

    public func load(
        envelopeRead: UpdateBootstrapEnvelopeReadResult,
        entriesRead: UpdateBootstrapBundleEntriesReadResult
    ) throws -> UpdateBootstrapEnvelope {
        let envelope = try requireEnvelope(envelopeRead)
        let entries = try requireEntries(entriesRead)
        do {
            try UpdateBootstrapBundleClosurePolicy.validate(
                envelope: envelope,
                entries: entries
            )
        } catch let error as UpdateBootstrapBundleClosureError {
            throw LoadUpdateBootstrapBundleError.closureInvalid(error)
        }
        return envelope
    }

    private func requireEnvelope(
        _ result: UpdateBootstrapEnvelopeReadResult
    ) throws -> UpdateBootstrapEnvelope {
        switch result {
        case .loaded(let envelope):
            return envelope
        case .missing(let path):
            throw LoadUpdateBootstrapBundleError.envelopeMissing(path: path)
        case .unexpectedPathState(let path, let state):
            throw LoadUpdateBootstrapBundleError.envelopeUnexpectedPathState(
                path: path,
                state: state
            )
        case .inspectionFailed(let path, let reason):
            throw LoadUpdateBootstrapBundleError.envelopeInspectionFailed(
                path: path,
                reason: reason
            )
        case .readFailed(let path, let reason):
            throw LoadUpdateBootstrapBundleError.envelopeReadFailed(
                path: path,
                reason: reason
            )
        case .decodeFailed(let path, let reason):
            throw LoadUpdateBootstrapBundleError.envelopeDecodeFailed(
                path: path,
                reason: reason
            )
        }
    }

    private func requireEntries(
        _ result: UpdateBootstrapBundleEntriesReadResult
    ) throws -> [UpdateBootstrapBundleEntry] {
        switch result {
        case .loaded(let entries):
            return entries
        case .rootMissing(let path):
            throw LoadUpdateBootstrapBundleError.bundleRootMissing(path: path)
        case .unexpectedRootPathState(let path, let state):
            throw LoadUpdateBootstrapBundleError.bundleRootUnexpectedPathState(
                path: path,
                state: state
            )
        case .rootInspectionFailed(let path, let reason):
            throw LoadUpdateBootstrapBundleError.bundleRootInspectionFailed(
                path: path,
                reason: reason
            )
        case .listingFailed(let path, let reason):
            throw LoadUpdateBootstrapBundleError.bundleListingFailed(
                path: path,
                reason: reason
            )
        }
    }
}
