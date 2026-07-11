import Contracts
import Foundation
@testable import OutboundAdapters
import XCTest

final class FileRuntimeGuestAddressResourceStoreTests: XCTestCase {
    func testMissingDocumentStaysMissing() {
        let store = makeStore().store

        let resource = store.loadGuestAddressResource()

        XCTAssertEqual(resource.state, .missing)
        XCTAssertNil(resource.read)
        XCTAssertTrue(resource.readError?.contains("document missing") == true)
    }

    func testPutPersistsEndpointForAnotherReader() throws {
        let fixture = makeStore()

        let written = try fixture.store.putGuestAddressResource(address: " 192.168.64.11\n")
        let loaded = FileRuntimeGuestAddressResourceStore(
            documentURL: fixture.url
        ).loadGuestAddressResource()

        XCTAssertEqual(loaded, written)
        XCTAssertEqual(loaded.read?.loadedAddress, "192.168.64.11")
        XCTAssertEqual(loaded.read?.source, .platformAgent)
    }

    func testInvalidDocumentStaysFailedInsteadOfMissing() throws {
        let fixture = makeStore()
        try FileManager.default.createDirectory(
            at: fixture.url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("not-json".utf8).write(to: fixture.url)

        let resource = fixture.store.loadGuestAddressResource()

        XCTAssertEqual(resource.state, .failed)
        XCTAssertTrue(resource.readError?.contains("read failed") == true)
    }

    func testNonLoadedDocumentIsInvalid() throws {
        let fixture = makeStore()
        try FileManager.default.createDirectory(
            at: fixture.url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let document = RuntimeGuestAddressReadResult.missing("not ready")
        try JSONEncoder().encode(document).write(to: fixture.url)

        let resource = fixture.store.loadGuestAddressResource()

        XCTAssertEqual(resource.state, .failed)
        XCTAssertTrue(resource.readError?.contains("document is invalid") == true)
    }

    func testEmptyPutDoesNotCreateLoadedOrFailedOwnerDocument() throws {
        let fixture = makeStore()

        let result = try fixture.store.putGuestAddressResource(address: " \n")

        XCTAssertEqual(result.state, .failed)
        XCTAssertEqual(fixture.store.loadGuestAddressResource().state, .missing)
    }

    private func makeStore() -> (store: FileRuntimeGuestAddressResourceStore, url: URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileRuntimeGuestAddressResourceStoreTests-\(UUID().uuidString)")
            .appendingPathComponent("runtime-endpoint.json")
        return (FileRuntimeGuestAddressResourceStore(documentURL: url), url)
    }
}
