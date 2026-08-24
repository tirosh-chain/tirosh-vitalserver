import Application
import Contracts
import Domain
import XCTest

final class BindPlatformAgentUpdateBootstrapApplyUseCaseTests: XCTestCase {
    func testCommitPersistFailureLeavesSelectionVerifiedAndRetryable() {
        let store = InMemorySelectionStore(current: verified())
        store.failNextPersist = true

        XCTAssertThrowsError(
            try BindPlatformAgentUpdateBootstrapApplyUseCase().bind(
                observedBundlePath: "/tmp/update.tar.gz",
                mintRequestId: { "request-1" },
                observedAt: "2026-08-24T00:00:01Z",
                currentRead: store.read(),
                persist: store.persist
            )
        ) { error in
            guard case .persistFailed = error as? BindPlatformAgentUpdateBootstrapApplyError
            else {
                return XCTFail("expected persist failure, got \(error)")
            }
        }
        XCTAssertEqual(
            store.current?.state,
            PlatformAgentUpdateBootstrapVerifiedSelectionContract.stateVerified
        )
        XCTAssertNil(store.current?.boundRequestId)
        XCTAssertEqual(store.persistCount, 1)

        store.failNextPersist = false
        let requestId = try! BindPlatformAgentUpdateBootstrapApplyUseCase()
            .bind(
                observedBundlePath: "/tmp/update.tar.gz",
                mintRequestId: { "request-1" },
                observedAt: "2026-08-24T00:00:02Z",
                currentRead: store.read(),
                persist: store.persist
            )
        XCTAssertEqual(requestId, "request-1")
        XCTAssertEqual(
            store.current?.state,
            PlatformAgentUpdateBootstrapVerifiedSelectionContract
                .stateApplyCommitted
        )
        XCTAssertEqual(store.persistCount, 2)
    }

    func testCommitPersistsOnceAndResumeDoesNotWrite() throws {
        let store = InMemorySelectionStore(current: verified())
        let first = try BindPlatformAgentUpdateBootstrapApplyUseCase().bind(
            observedBundlePath: "/tmp/update.tar.gz",
            mintRequestId: { "request-1" },
            observedAt: "2026-08-24T00:00:01Z",
            currentRead: store.read(),
            persist: store.persist
        )
        XCTAssertEqual(first, "request-1")
        XCTAssertEqual(store.persistCount, 1)

        let resumed = try BindPlatformAgentUpdateBootstrapApplyUseCase().bind(
            observedBundlePath: "/tmp/other.tar.gz",
            mintRequestId: { "request-2" },
            observedAt: "2026-08-24T00:00:02Z",
            currentRead: store.read(),
            persist: store.persist
        )
        XCTAssertEqual(resumed, "request-1")
        XCTAssertEqual(store.persistCount, 1)
        XCTAssertEqual(store.current?.boundRequestId, "request-1")
    }

    func testMissingCurrentSelectionDoesNotInventLatestOrPathMatch() {
        let store = InMemorySelectionStore(current: nil)
        XCTAssertThrowsError(
            try BindPlatformAgentUpdateBootstrapApplyUseCase().bind(
                observedBundlePath: "/tmp/update.tar.gz",
                mintRequestId: { "request-1" },
                observedAt: "2026-08-24T00:00:01Z",
                currentRead: store.read(),
                persist: store.persist
            )
        ) { error in
            XCTAssertEqual(
                error as? BindPlatformAgentUpdateBootstrapApplyError,
                .missing(path: "/tmp/current.json")
            )
        }
        XCTAssertEqual(store.persistCount, 0)
    }

    func testKeepsReadFailureKindsDistinctFromMissing() {
        let cases: [(
            PlatformAgentUpdateBootstrapVerifiedSelectionReadResult,
            BindPlatformAgentUpdateBootstrapApplyError
        )] = [
            (
                .permissionDenied(path: "/tmp/current.json", reason: "EACCES"),
                .permissionDenied(path: "/tmp/current.json", reason: "EACCES")
            ),
            (
                .decodeFailed(path: "/tmp/current.json", reason: "not json"),
                .decodeFailed(path: "/tmp/current.json", reason: "not json")
            ),
            (
                .readFailed(path: "/tmp/current.json", reason: "EIO"),
                .readFailed(path: "/tmp/current.json", reason: "EIO")
            ),
        ]
        for (read, expected) in cases {
            XCTAssertThrowsError(
                try BindPlatformAgentUpdateBootstrapApplyUseCase().bind(
                    observedBundlePath: "/tmp/update.tar.gz",
                    mintRequestId: { "request-1" },
                    observedAt: "2026-08-24T00:00:01Z",
                    currentRead: read,
                    persist: { _ in }
                )
            ) { error in
                XCTAssertEqual(
                    error as? BindPlatformAgentUpdateBootstrapApplyError,
                    expected
                )
            }
        }
    }

    func testSpentSelectionIsNotReappliedByANewRequest() throws {
        let store = InMemorySelectionStore(current: verified())
        _ = try BindPlatformAgentUpdateBootstrapApplyUseCase().bind(
            observedBundlePath: "/tmp/update.tar.gz",
            mintRequestId: { "request-1" },
            observedAt: "2026-08-24T00:00:01Z",
            currentRead: store.read(),
            persist: store.persist
        )
        try SpendPlatformAgentUpdateBootstrapApplyUseCase().spend(
            requestId: "request-1",
            observedAt: "2026-08-24T00:00:02Z",
            currentRead: store.read(),
            persist: store.persist
        )

        XCTAssertThrowsError(
            try BindPlatformAgentUpdateBootstrapApplyUseCase().bind(
                observedBundlePath: "/tmp/update.tar.gz",
                mintRequestId: { "request-2" },
                observedAt: "2026-08-24T00:00:03Z",
                currentRead: store.read(),
                persist: store.persist
            )
        ) { error in
            XCTAssertEqual(
                error as? BindPlatformAgentUpdateBootstrapApplyError,
                .stale
            )
        }
    }
}

final class SpendPlatformAgentUpdateBootstrapApplyUseCaseTests: XCTestCase {
    func testSpendPersistFailureLeavesApplyCommittedRetryable() throws {
        let store = InMemorySelectionStore(current: verified())
        _ = try BindPlatformAgentUpdateBootstrapApplyUseCase().bind(
            observedBundlePath: "/tmp/update.tar.gz",
            mintRequestId: { "request-1" },
            observedAt: "2026-08-24T00:00:01Z",
            currentRead: store.read(),
            persist: store.persist
        )
        store.failNextPersist = true
        XCTAssertThrowsError(
            try SpendPlatformAgentUpdateBootstrapApplyUseCase().spend(
                requestId: "request-1",
                observedAt: "2026-08-24T00:00:02Z",
                currentRead: store.read(),
                persist: store.persist
            )
        ) { error in
            guard case .persistFailed = error as? SpendPlatformAgentUpdateBootstrapApplyError
            else {
                return XCTFail("expected persist failure, got \(error)")
            }
        }
        XCTAssertEqual(
            store.current?.state,
            PlatformAgentUpdateBootstrapVerifiedSelectionContract
                .stateApplyCommitted
        )

        store.failNextPersist = false
        try SpendPlatformAgentUpdateBootstrapApplyUseCase().spend(
            requestId: "request-1",
            observedAt: "2026-08-24T00:00:03Z",
            currentRead: store.read(),
            persist: store.persist
        )
        XCTAssertEqual(
            store.current?.state,
            PlatformAgentUpdateBootstrapVerifiedSelectionContract.stateSpent
        )
    }
}

private final class InMemorySelectionStore: @unchecked Sendable {
    var current: PlatformAgentUpdateBootstrapVerifiedSelection?
    var persistCount = 0
    var failNextPersist = false

    init(current: PlatformAgentUpdateBootstrapVerifiedSelection?) {
        self.current = current
    }

    func read() -> PlatformAgentUpdateBootstrapVerifiedSelectionReadResult {
        if let current {
            return .loaded(current)
        }
        return .missing(path: "/tmp/current.json")
    }

    func persist(
        _ selection: PlatformAgentUpdateBootstrapVerifiedSelection
    ) throws {
        persistCount += 1
        if failNextPersist {
            throw NSError(domain: "test", code: persistCount)
        }
        current = selection
    }
}

private func verified() -> PlatformAgentUpdateBootstrapVerifiedSelection {
    PlatformAgentUpdateBootstrapVerifiedSelectionPolicy.verified(
        selectionId: "11111111-2222-3333-4444-555555555555",
        verificationInvocationId: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
        updateId: "update-42",
        canonicalPayloadSHA256: String(repeating: "ab", count: 32),
        observedBundlePath: "/tmp/update.tar.gz",
        observedAt: "2026-08-24T00:00:00Z"
    )
}
