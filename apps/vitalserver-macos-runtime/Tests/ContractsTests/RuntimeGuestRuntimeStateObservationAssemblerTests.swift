import Contracts
import Foundation
import XCTest

final class RuntimeGuestRuntimeStateObservationAssemblerTests: XCTestCase {
    func testLoadedDocumentIsFreshWithinExplicitStaleWindow() {
        let observation = RuntimeGuestRuntimeStateObservationAssembler.loaded(
            guestState(),
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_000),
            observedAt: Date(timeIntervalSince1970: 1_800_000_060),
            staleAfterSeconds: 60
        )

        XCTAssertEqual(observation.loadedState?.vmIP, "192.168.64.2")
        XCTAssertEqual(observation.freshState?.vmIP, "192.168.64.2")
        XCTAssertTrue(observation.isFresh)
        XCTAssertNil(observation.readIssue)
    }

    func testLoadedDocumentIsStaleAfterExplicitStaleWindow() {
        let observation = RuntimeGuestRuntimeStateObservationAssembler.loaded(
            guestState(),
            modifiedAt: Date(timeIntervalSince1970: 1_800_000_000),
            observedAt: Date(timeIntervalSince1970: 1_800_000_061),
            staleAfterSeconds: 60
        )

        XCTAssertEqual(observation.loadedState?.vmIP, "192.168.64.2")
        XCTAssertNil(observation.freshState)
        XCTAssertFalse(observation.isFresh)
        XCTAssertNil(observation.readIssue)
    }

    func testMissingLoadFailureAndMetadataFailureRemainDistinct() {
        let missing = RuntimeGuestRuntimeStateObservationAssembler.missing()
        XCTAssertNil(missing.loadedState)
        XCTAssertNil(missing.freshState)
        XCTAssertFalse(missing.isFresh)
        XCTAssertNil(missing.readIssue)

        let loadFailed = RuntimeGuestRuntimeStateObservationAssembler.loadFailed("decode failed")
        XCTAssertNil(loadFailed.loadedState)
        XCTAssertNil(loadFailed.freshState)
        XCTAssertFalse(loadFailed.isFresh)
        XCTAssertEqual(loadFailed.readIssue, .loadFailed("decode failed"))

        let metadataFailed = RuntimeGuestRuntimeStateObservationAssembler.metadataReadFailed(
            guestState(),
            message: "permission denied"
        )
        XCTAssertEqual(metadataFailed.loadedState?.vmIP, "192.168.64.2")
        XCTAssertNil(metadataFailed.freshState)
        XCTAssertFalse(metadataFailed.isFresh)
        XCTAssertEqual(metadataFailed.readIssue, .metadataReadFailed("permission denied"))
    }

    private func guestState() -> GuestRuntimeStateDocument {
        GuestRuntimeStateDocument(
            vmIP: "192.168.64.2",
            updatedAt: "2026-05-24T00:00:00Z",
            guestHTTP: "200",
            redisUIHTTP: "200",
            swaggerUIHTTP: "200"
        )
    }
}
