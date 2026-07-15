import Application
import Contracts
import XCTest

final class SynchronizeRuntimeEndpointUseCaseTests: XCTestCase {
    func testDecideCreatesEndpointMutationForCurrentLifecycle() throws {
        let decision = makeDecision(endpoint: .missing)

        let mutation = try XCTUnwrap(persistMutation(decision))
        XCTAssertEqual(mutation.runID, "boot-2")
        XCTAssertEqual(mutation.lifecycleRevision, 4)
        XCTAssertEqual(mutation.address, "192.168.64.12")
        XCTAssertEqual(mutation.observedAt, "2026-07-15T00:00:00Z")
        XCTAssertNil(mutation.expectedRevision)
    }

    func testDecideDoesNotRewriteMatchingEndpoint() {
        let current = endpointRecord(runID: "boot-2", lifecycleRevision: 3, revision: 7)

        XCTAssertEqual(makeDecision(endpoint: .loaded(current)), .unchanged(current))
    }

    func testDecideRebindsStaleEndpointEvenWhenAddressDidNotChange() throws {
        let stale = endpointRecord(runID: "boot-1", lifecycleRevision: 2, revision: 7)

        let mutation = try XCTUnwrap(persistMutation(makeDecision(
            endpoint: .stale(stale, reason: "run ID mismatch")
        )))

        XCTAssertEqual(mutation.runID, "boot-2")
        XCTAssertEqual(mutation.expectedRevision, 7)
    }

    func testDecidePreservesMissingBootstrapAsUnavailable() {
        let missing = RuntimeGuestAddressReadResult.missing("vm-ip missing")

        XCTAssertEqual(
            makeDecision(bootstrap: missing, endpoint: .missing),
            .bootstrapUnavailable(missing)
        )
    }

    private func makeDecision(
        bootstrap: RuntimeGuestAddressReadResult = .loaded(
            address: "192.168.64.12",
            source: .platformAgent
        ),
        endpoint: RuntimeEndpointStateReadResult
    ) -> RuntimeEndpointSynchronizationResult {
        SynchronizeRuntimeEndpointUseCase().decide(
            bootstrap: bootstrap,
            lifecycleRead: .loaded(RuntimeVMLifecycleStateRecord(
                document: RuntimeVMLifecycleDocument(
                    state: .running,
                    operation: .startServices,
                    operationID: "operation-2",
                    bootID: "boot-2",
                    startedAt: "2026-07-15T00:00:00Z",
                    updatedAt: "2026-07-15T00:00:01Z",
                    deadlineAt: nil,
                    terminalReason: nil,
                    message: "running"
                ),
                revision: 4
            )),
            endpointRead: endpoint,
            observedAt: "2026-07-15T00:00:00Z"
        )
    }

    private func persistMutation(
        _ decision: RuntimeEndpointSynchronizationResult
    ) -> RuntimeEndpointStateMutation? {
        guard case .persist(let mutation) = decision else { return nil }
        return mutation
    }

    private func endpointRecord(
        runID: String,
        lifecycleRevision: Int,
        revision: Int
    ) -> RuntimeEndpointStateRecord {
        RuntimeEndpointStateRecord(
            runID: runID,
            lifecycleRevision: lifecycleRevision,
            address: "192.168.64.12",
            source: .platformAgent,
            observedAt: "2026-07-15T00:00:00Z",
            revision: revision
        )
    }
}
