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

    func testFileModifiedAtReaderReportsTimestampAndFailureDistinctly() {
        let url = URL(fileURLWithPath: "/product/run/runtime-state.json")
        let fileStore = RuntimeFileStoreSpy()
        fileStore.files[url] = Data("{}".utf8)
        fileStore.modificationDates[url] = Date(timeIntervalSince1970: 1_800_000_120)

        var result = RuntimeFileModifiedAtReader(url: url, fileStore: fileStore).read()
        XCTAssertEqual(result.updatedAt, "2027-01-15T08:02:00Z")
        XCTAssertNil(result.readError)

        fileStore.modificationDateErrors[url] = CocoaError(.fileReadNoPermission)
        result = RuntimeFileModifiedAtReader(url: url, fileStore: fileStore).read()
        XCTAssertNil(result.updatedAt)
        XCTAssertTrue(result.readError?.contains("mtime-read-failed path=/product/run/runtime-state.json") == true)
        XCTAssertTrue(result.readError?.contains("reason=") == true)
    }

    func testFileModifiedAtReaderPreservesPathStateFailuresBeforeReadingMTime() {
        let url = URL(fileURLWithPath: "/product/run/runtime-state.json")
        let fileStore = RuntimeFileStoreSpy()

        var result = RuntimeFileModifiedAtReader(url: url, fileStore: fileStore).read()
        XCTAssertNil(result.updatedAt)
        XCTAssertEqual(
            result.readError,
            "file modified-at path missing path=/product/run/runtime-state.json"
        )

        fileStore.pathStates[url.path] = .inspectFailed("permission denied")
        result = RuntimeFileModifiedAtReader(url: url, fileStore: fileStore).read()
        XCTAssertNil(result.updatedAt)
        XCTAssertEqual(
            result.readError,
            "file modified-at path inspection failed path=/product/run/runtime-state.json reason=permission denied"
        )

        fileStore.pathStates[url.path] = .directory
        result = RuntimeFileModifiedAtReader(url: url, fileStore: fileStore).read()
        XCTAssertNil(result.updatedAt)
        XCTAssertEqual(
            result.readError,
            "file modified-at path state is unexpected path=/product/run/runtime-state.json state=directory"
        )
    }
}
