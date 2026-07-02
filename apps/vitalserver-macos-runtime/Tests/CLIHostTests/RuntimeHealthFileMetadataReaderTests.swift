import Application
import Contracts
import Foundation
import OutboundAdapters
import XCTest
import Errors

final class RuntimeHealthFileMetadataReaderTests: XCTestCase {
    func testContainerLogsMetadataReportsMissingWithoutInventingError() {
        let fileStore = RuntimeFileStoreSpy()
        let metadata = RuntimeContainerLogsMetadataReader(
            url: URL(fileURLWithPath: "/product/run/container-logs.log"),
            fileStore: fileStore
        ).read()

        XCTAssertFalse(metadata.present)
        XCTAssertNil(metadata.bytes)
        XCTAssertNil(metadata.updatedAt)
        XCTAssertNil(metadata.error)
    }

    func testContainerLogsMetadataReportsPathInspectionFailure() {
        let url = URL(fileURLWithPath: "/product/run/container-logs.log")
        let fileStore = RuntimeFileStoreSpy()
        fileStore.pathStates[url.path] = .inspectFailed("permission denied")

        let metadata = RuntimeContainerLogsMetadataReader(url: url, fileStore: fileStore).read()

        XCTAssertFalse(metadata.present)
        XCTAssertNil(metadata.bytes)
        XCTAssertNil(metadata.updatedAt)
        XCTAssertEqual(
            metadata.error,
            "container logs path inspection failed path=/product/run/container-logs.log reason=permission denied"
        )
    }

    func testContainerLogsMetadataReportsUnexpectedPathState() {
        let url = URL(fileURLWithPath: "/product/run/container-logs.log")
        let fileStore = RuntimeFileStoreSpy()
        fileStore.pathStates[url.path] = .directory

        let metadata = RuntimeContainerLogsMetadataReader(url: url, fileStore: fileStore).read()

        XCTAssertFalse(metadata.present)
        XCTAssertNil(metadata.bytes)
        XCTAssertNil(metadata.updatedAt)
        XCTAssertEqual(
            metadata.error,
            "container logs path state is unexpected path=/product/run/container-logs.log state=directory"
        )
    }

    func testContainerLogsMetadataReadsSizeAndModifiedAt() {
        let url = URL(fileURLWithPath: "/product/run/container-logs.log")
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[url] = Data("container logs".utf8)
        fileStore.modificationDates[url] = Date(timeIntervalSince1970: 1_800_000_060)

        let metadata = RuntimeContainerLogsMetadataReader(url: url, fileStore: fileStore).read()

        XCTAssertTrue(metadata.present)
        XCTAssertEqual(metadata.bytes, 14)
        XCTAssertEqual(metadata.updatedAt, "2027-01-15T08:01:00Z")
        XCTAssertNil(metadata.error)
    }

    func testContainerLogsMetadataKeepsSizeAndMTimeFailuresVisible() {
        let url = URL(fileURLWithPath: "/product/run/container-logs.log")
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[url] = Data("container logs".utf8)
        fileStore.fileSizeErrors[url] = CocoaError(.fileReadNoPermission)
        fileStore.modificationDateErrors[url] = CocoaError(.fileReadNoPermission)

        let metadata = RuntimeContainerLogsMetadataReader(url: url, fileStore: fileStore).read()

        XCTAssertTrue(metadata.present)
        XCTAssertNil(metadata.bytes)
        XCTAssertNil(metadata.updatedAt)
        XCTAssertTrue(metadata.error?.contains("size-read-failed reason=") == true)
        XCTAssertTrue(metadata.error?.contains("mtime-read-failed reason=") == true)
    }

}
