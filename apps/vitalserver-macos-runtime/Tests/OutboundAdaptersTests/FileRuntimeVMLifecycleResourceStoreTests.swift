import Contracts
import Foundation
@testable import OutboundAdapters
import XCTest

final class FileRuntimeVMLifecycleResourceStoreTests: XCTestCase {
    func testMissingDocumentStaysMissing() {
        let store = makeStore().store

        let resource = store.loadVMLifecycleResource()

        XCTAssertEqual(resource.state, .missing)
        XCTAssertNil(resource.document)
        XCTAssertTrue(resource.readError?.contains("document missing") == true)
    }

    func testWritePersistsLifecycleForAnotherReader() throws {
        let fixture = makeStore(now: Date(timeIntervalSince1970: 1_700_000_000))

        let written = try fixture.store.writeVMLifecycleResource(
            state: .starting,
            operation: .startServices,
            message: "starting",
            bootWindowSeconds: 60
        )
        let loaded = FileRuntimeVMLifecycleResourceStore(
            documentURL: fixture.url
        ).loadVMLifecycleResource()

        XCTAssertEqual(loaded, written)
        XCTAssertEqual(loaded.document?.state, .starting)
        XCTAssertEqual(loaded.document?.message, "starting")
    }

    func testInvalidDocumentStaysFailedInsteadOfMissing() throws {
        let fixture = makeStore()
        try FileManager.default.createDirectory(
            at: fixture.url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: fixture.url)

        let resource = fixture.store.loadVMLifecycleResource()

        XCTAssertEqual(resource.state, .failed)
        XCTAssertTrue(resource.readError?.contains("read failed") == true)
    }

    func testNonStartingWriteRequiresExistingLifecycle() {
        let store = makeStore().store

        XCTAssertThrowsError(try store.writeVMLifecycleResource(state: .running)) { error in
            XCTAssertEqual(
                error as? RuntimeVMLifecycleResourceWriteError,
                .missingDocumentForState(.running)
            )
        }
    }

    func testPutPreservesExplicitOperationIdentity() throws {
        let fixture = makeStore()
        let document = RuntimeVMLifecycleDocument(
            state: .running,
            operation: .install,
            operationID: "operation-1",
            bootID: "boot-1",
            startedAt: "2026-07-11T00:00:00Z",
            updatedAt: "2026-07-11T00:01:00Z"
        )

        _ = try fixture.store.putVMLifecycleResource(document)

        XCTAssertEqual(fixture.store.loadVMLifecycleResource(), .loaded(document))
    }

    private func makeStore(
        now: Date = Date(timeIntervalSince1970: 0)
    ) -> (store: FileRuntimeVMLifecycleResourceStore, url: URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileRuntimeVMLifecycleResourceStoreTests-\(UUID().uuidString)")
            .appendingPathComponent("runtime-provider-lifecycle.json")
        return (
            FileRuntimeVMLifecycleResourceStore(
                documentURL: url,
                now: { now }
            ),
            url
        )
    }
}
