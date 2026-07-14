import Application
import Contracts
import Foundation
import RuntimeControl

public struct SQLiteRuntimeGuestAddressResourceStore:
    RuntimeGuestAddressProvider,
    RuntimeGuestAddressResourceReading,
    RuntimeGuestAddressResourceWriting,
    @unchecked Sendable
{
    private let endpointRepository: SQLiteRuntimeEndpointStateRepository
    private let lifecycleRepository: SQLiteRuntimeVMLifecycleStateRepository
    private let now: @Sendable () -> Date

    public init(
        databaseURL: URL,
        lifecycleTransitionDecider: any RuntimeVMLifecycleTransitionDeciding,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.endpointRepository = SQLiteRuntimeEndpointStateRepository(databaseURL: databaseURL)
        self.lifecycleRepository = SQLiteRuntimeVMLifecycleStateRepository(
            databaseURL: databaseURL,
            transitionDecider: lifecycleTransitionDecider
        )
        self.now = now
    }

    public func readGuestAddress() -> RuntimeGuestAddressReadResult {
        RuntimeGuestAddressResourceReadMapper.readResult(from: loadGuestAddressResource())
    }

    public func loadGuestAddressResource() -> RuntimeGuestAddressResourceState {
        switch endpointRepository.loadRuntimeEndpointState() {
        case .missing:
            return .missing(readError: "Runtime endpoint SQLite state is missing")
        case .loaded(let endpoint):
            return .loaded(.loaded(address: endpoint.address, source: endpoint.source))
        case .stale(_, let reason):
            return .loaded(.stale(reason))
        case .failed(let reason):
            return .failed(readError: reason)
        }
    }

    @discardableResult
    public func putGuestAddressResource(address: String) throws -> RuntimeGuestAddressResourceState {
        let lifecycle: RuntimeVMLifecycleStateRecord
        switch lifecycleRepository.loadVMLifecycleState() {
        case .missing:
            throw SQLiteRuntimeEndpointStateRepositoryError.lifecycleMissing
        case .loaded(let record):
            lifecycle = record
        case .failed(let reason):
            throw SQLiteRuntimeEndpointStateRepositoryError.writeFailed(
                path: endpointRepository.databaseURL.path,
                reason: reason
            )
        }
        let expectedRevision: Int?
        switch endpointRepository.loadRuntimeEndpointState() {
        case .missing:
            expectedRevision = nil
        case .loaded(let record), .stale(let record, _):
            expectedRevision = record.revision
        case .failed(let reason):
            throw SQLiteRuntimeEndpointStateRepositoryError.writeFailed(
                path: endpointRepository.databaseURL.path,
                reason: reason
            )
        }
        let endpoint = try endpointRepository.saveRuntimeEndpointState(RuntimeEndpointStateMutation(
            runID: lifecycle.document.bootID ?? "",
            lifecycleRevision: lifecycle.revision,
            address: address,
            source: .platformAgent,
            observedAt: ISO8601DateFormatter().string(from: now()),
            expectedRevision: expectedRevision
        ))
        return .loaded(.loaded(address: endpoint.address, source: endpoint.source))
    }
}
