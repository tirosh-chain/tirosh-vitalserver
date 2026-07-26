import Contracts

public enum RuntimeEndpointSynchronizationResult: Equatable, Sendable {
    case bootstrapUnavailable(RuntimeGuestAddressReadResult)
    case lifecycleUnavailable(String)
    case unchanged(RuntimeEndpointStateRecord)
    case persist(RuntimeEndpointStateMutation)
    case failed(String)
}

public struct SynchronizeRuntimeEndpointUseCase {
    public init() {}

    public func decide(
        bootstrap: RuntimeGuestAddressReadResult,
        lifecycleRead: RuntimeVMLifecycleStateReadResult,
        endpointRead: RuntimeEndpointStateReadResult,
        observedAt: String
    ) -> RuntimeEndpointSynchronizationResult {
        guard bootstrap.state == .loaded,
              let address = bootstrap.loadedAddress else {
            return .bootstrapUnavailable(bootstrap)
        }

        let lifecycle: RuntimeVMLifecycleStateRecord
        switch lifecycleRead {
        case .missing:
            return .lifecycleUnavailable("VM lifecycle SQLite state is missing")
        case .failed(let reason):
            return .lifecycleUnavailable(reason)
        case .loaded(let record):
            lifecycle = record
        }

        guard let runID = lifecycle.document.bootID, !runID.isEmpty else {
            return .lifecycleUnavailable("VM lifecycle boot ID is missing")
        }

        let expectedRevision: Int?
        switch endpointRead {
        case .missing:
            expectedRevision = nil
        case .failed(let reason):
            return .failed(reason)
        case .loaded(let endpoint):
            if endpoint.runID == runID,
               endpoint.lifecycleRevision <= lifecycle.revision,
               endpoint.address == address {
                return .unchanged(endpoint)
            }
            expectedRevision = endpoint.revision
        case .stale(let endpoint, _):
            expectedRevision = endpoint.revision
        }

        return .persist(RuntimeEndpointStateMutation(
            runID: runID,
            lifecycleRevision: lifecycle.revision,
            address: address,
            source: .platformAgent,
            observedAt: observedAt,
            expectedRevision: expectedRevision
        ))
    }
}
