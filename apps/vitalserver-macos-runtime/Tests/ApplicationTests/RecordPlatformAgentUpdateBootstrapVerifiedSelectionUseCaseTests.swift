import Application
import Contracts
import Domain
import XCTest

final class RecordPlatformAgentUpdateBootstrapVerifiedSelectionUseCaseTests:
    XCTestCase
{
    func testPersistsVerifiedSelectionFromSuccessfulVerificationIdentities()
        throws
    {
        var persisted: PlatformAgentUpdateBootstrapVerifiedSelection?
        let selection = try
            RecordPlatformAgentUpdateBootstrapVerifiedSelectionUseCase()
            .record(
                selectionId: selectionId,
                verificationInvocationId: invocationId,
                updateId: "update-42",
                canonicalPayloadSHA256: digest,
                observedBundlePath: "/tmp/update.tar.gz",
                observedAt: "2026-08-24T00:00:00Z",
                currentRead: .missing(path: "/tmp/current.json"),
                persist: { persisted = $0 }
            )

        XCTAssertEqual(selection.selectionId, selectionId)
        XCTAssertEqual(
            selection.state,
            PlatformAgentUpdateBootstrapVerifiedSelectionContract.stateVerified
        )
        XCTAssertEqual(persisted, selection)
        XCTAssertNil(selection.boundRequestId)
    }

    func testPersistFailureLeavesStoreUnchanged() {
        let store: PlatformAgentUpdateBootstrapVerifiedSelection? = nil
        XCTAssertThrowsError(
            try RecordPlatformAgentUpdateBootstrapVerifiedSelectionUseCase()
                .record(
                    selectionId: selectionId,
                    verificationInvocationId: invocationId,
                    updateId: "update-42",
                    canonicalPayloadSHA256: digest,
                    observedBundlePath: "/tmp/update.tar.gz",
                    observedAt: "2026-08-24T00:00:00Z",
                    currentRead: .missing(path: "/tmp/current.json"),
                    persist: { _ in
                        throw NSError(domain: "test", code: 1)
                    }
                )
        ) { error in
            guard case .persistFailed = error as? RecordPlatformAgentUpdateBootstrapVerifiedSelectionError
            else {
                return XCTFail("expected persist failure, got \(error)")
            }
        }
        XCTAssertNil(store)
    }

    func testDoesNotOverwriteUnreadableCurrentStore() {
        var persisted = false
        XCTAssertThrowsError(
            try RecordPlatformAgentUpdateBootstrapVerifiedSelectionUseCase()
                .record(
                    selectionId: selectionId,
                    verificationInvocationId: invocationId,
                    updateId: "update-42",
                    canonicalPayloadSHA256: digest,
                    observedBundlePath: "/tmp/update.tar.gz",
                    observedAt: "2026-08-24T00:00:00Z",
                    currentRead: .permissionDenied(
                        path: "/tmp/current.json",
                        reason: "EACCES"
                    ),
                    persist: { _ in persisted = true }
                )
        ) { error in
            XCTAssertEqual(
                error as? RecordPlatformAgentUpdateBootstrapVerifiedSelectionError,
                .permissionDenied(path: "/tmp/current.json", reason: "EACCES")
            )
        }
        XCTAssertFalse(persisted)
    }

    func testDoesNotReplaceApplyCommittedSelection() throws {
        let committed = try PlatformAgentUpdateBootstrapVerifiedSelectionPolicy
            .commitApply(
                selection: PlatformAgentUpdateBootstrapVerifiedSelectionPolicy
                    .verified(
                        selectionId: selectionId,
                        verificationInvocationId: invocationId,
                        updateId: "update-42",
                        canonicalPayloadSHA256: digest,
                        observedBundlePath: "/tmp/update.tar.gz",
                        observedAt: "2026-08-24T00:00:00Z"
                    ),
                requestId: "request-1",
                observedBundlePath: "/tmp/update.tar.gz",
                observedAt: "2026-08-24T00:00:01Z"
            ).selection
        var persisted = false
        XCTAssertThrowsError(
            try RecordPlatformAgentUpdateBootstrapVerifiedSelectionUseCase()
                .record(
                    selectionId: "22222222-3333-4444-5555-666666666666",
                    verificationInvocationId:
                        "bbbbbbbb-cccc-dddd-eeee-ffffffffffff",
                    updateId: "update-43",
                    canonicalPayloadSHA256: String(repeating: "cd", count: 32),
                    observedBundlePath: "/tmp/other.tar.gz",
                    observedAt: "2026-08-24T00:01:00Z",
                    currentRead: .loaded(committed),
                    persist: { _ in persisted = true }
                )
        ) { error in
            XCTAssertEqual(
                error as? RecordPlatformAgentUpdateBootstrapVerifiedSelectionError,
                .inFlight(requestId: "request-1")
            )
        }
        XCTAssertFalse(persisted)
    }

    func testInvalidCurrentStoreIsNotReportedAsPersistFailure() {
        let invalidCurrent = PlatformAgentUpdateBootstrapVerifiedSelection(
            schemaVersion:
                PlatformAgentUpdateBootstrapVerifiedSelectionContract
                .schemaVersion,
            producer: "not-mac-platform-agent",
            selectionId: selectionId,
            verificationInvocationId: invocationId,
            updateId: "update-42",
            canonicalPayloadSHA256: digest,
            observedBundlePath: "/tmp/update.tar.gz",
            state: PlatformAgentUpdateBootstrapVerifiedSelectionContract
                .stateVerified,
            observedAt: "2026-08-24T00:00:00Z"
        )
        var persisted = false
        XCTAssertThrowsError(
            try RecordPlatformAgentUpdateBootstrapVerifiedSelectionUseCase()
                .record(
                    selectionId: selectionId,
                    verificationInvocationId: invocationId,
                    updateId: "update-42",
                    canonicalPayloadSHA256: digest,
                    observedBundlePath: "/tmp/update.tar.gz",
                    observedAt: "2026-08-24T00:00:00Z",
                    currentRead: .loaded(invalidCurrent),
                    persist: { _ in persisted = true }
                )
        ) { error in
            XCTAssertEqual(
                error as? RecordPlatformAgentUpdateBootstrapVerifiedSelectionError,
                .invalid(
                    reason: String(
                        describing:
                            PlatformAgentUpdateBootstrapVerifiedSelectionValidationError
                            .unexpectedProducer("not-mac-platform-agent")
                    )
                )
            )
        }
        XCTAssertFalse(persisted)
    }

    func testDoesNotPersistWhenObservedPathIsNotAbsolute() {
        var persisted = false
        XCTAssertThrowsError(
            try RecordPlatformAgentUpdateBootstrapVerifiedSelectionUseCase()
                .record(
                    selectionId: selectionId,
                    verificationInvocationId: invocationId,
                    updateId: "update-42",
                    canonicalPayloadSHA256: digest,
                    observedBundlePath: "update.tar.gz",
                    observedAt: "2026-08-24T00:00:00Z",
                    currentRead: .missing(path: "/tmp/current.json"),
                    persist: { _ in persisted = true }
                )
        ) { error in
            XCTAssertEqual(
                error as? RecordPlatformAgentUpdateBootstrapVerifiedSelectionError,
                .invalidObservedBundlePath("update.tar.gz")
            )
        }
        XCTAssertFalse(persisted)
    }

    private var selectionId: String {
        "11111111-2222-3333-4444-555555555555"
    }

    private var invocationId: String {
        "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee"
    }

    private var digest: String {
        String(repeating: "ab", count: 32)
    }
}
