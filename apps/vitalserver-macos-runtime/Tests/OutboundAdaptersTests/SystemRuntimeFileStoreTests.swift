import Application
import Contracts
import Domain
import OutboundAdapters
import XCTest
import Errors

final class SystemRuntimeFileStoreTests: XCTestCase {
    func testFileAndDirectoryExistenceAreDistinct() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = directory.appendingPathComponent("value.txt")
        let store = SystemRuntimeFileStore()

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("value".utf8).write(to: file)

        XCTAssertTrue(store.directoryExists(directory))
        XCTAssertFalse(store.fileExists(directory))
        XCTAssertTrue(store.fileExists(file))
        XCTAssertFalse(store.directoryExists(file))

        try FileManager.default.removeItem(at: directory)
    }

    func testReadsDataAndText() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = directory.appendingPathComponent("value.txt")
        let store = SystemRuntimeFileStore()

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: file)

        XCTAssertEqual(try store.readUTF8Text(file), "hello")
        XCTAssertEqual(try store.readData(file), Data("hello".utf8))
        XCTAssertEqual(try store.fileSize(file), 5)

        try FileManager.default.removeItem(at: directory)
    }

    func testWritesCopiesMovesListsAndRemovesFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = directory.appendingPathComponent("source.txt")
        let copy = directory.appendingPathComponent("copy.txt")
        let moved = directory.appendingPathComponent("moved.txt")
        let store = SystemRuntimeFileStore()

        try store.createDirectory(at: directory, withIntermediateDirectories: true)
        try store.writeData(Data("payload".utf8), to: source, options: [])
        try store.copyItem(at: source, to: copy)
        try store.moveItem(at: copy, to: moved)

        let names = try store.contentsOfDirectory(at: directory, skipsHiddenFiles: false).map(\.lastPathComponent)

        XCTAssertTrue(names.contains("source.txt"))
        XCTAssertTrue(names.contains("moved.txt"))
        XCTAssertEqual(try store.readUTF8Text(moved), "payload")

        try store.removeItem(at: moved)
        XCTAssertFalse(store.fileExists(moved))

        try FileManager.default.removeItem(at: directory)
    }

    func testChildDirectoriesFiltersByNameAndSkipsHiddenFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let matching = directory.appendingPathComponent("runtime-before-1", isDirectory: true)
        let hiddenMatching = directory.appendingPathComponent(".runtime-before-2", isDirectory: true)
        let nonMatching = directory.appendingPathComponent("runtime-other", isDirectory: true)
        let matchingFile = directory.appendingPathComponent("file-before-1")
        let store = SystemRuntimeFileStore()

        try store.createDirectory(at: matching, withIntermediateDirectories: true)
        try store.createDirectory(at: hiddenMatching, withIntermediateDirectories: true)
        try store.createDirectory(at: nonMatching, withIntermediateDirectories: true)
        try store.writeData(Data("value".utf8), to: matchingFile, options: [])

        XCTAssertEqual(
            try store.childDirectories(
                at: directory,
                nameContains: "-before-",
                skipsHiddenFiles: true
            ).map(\.lastPathComponent),
            ["runtime-before-1"]
        )
        XCTAssertEqual(
            Set(try store.childDirectories(
                at: directory,
                nameContains: "-before-",
                skipsHiddenFiles: false
            ).map(\.lastPathComponent)),
            ["runtime-before-1", ".runtime-before-2"]
        )

        try FileManager.default.removeItem(at: directory)
    }

    func testRecursiveRegularFileSizeSumsVisibleRegularFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nested = directory.appendingPathComponent("nested", isDirectory: true)
        let visible = nested.appendingPathComponent("visible.txt")
        let hidden = nested.appendingPathComponent(".hidden.txt")
        let store = SystemRuntimeFileStore()

        try store.createDirectory(at: nested, withIntermediateDirectories: true)
        try store.writeData(Data(repeating: 1, count: 3), to: visible, options: [])
        try store.writeData(Data(repeating: 1, count: 5), to: hidden, options: [])

        XCTAssertEqual(try store.recursiveRegularFileSize(at: directory, skipsHiddenFiles: true), 3)
        XCTAssertEqual(try store.recursiveRegularFileSize(at: directory, skipsHiddenFiles: false), 8)

        try FileManager.default.removeItem(at: directory)
    }

    func testStorageUsageReturnsUnavailableWhenAvailableCapacityIsMissing() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let provider = SystemRuntimeStorageUsageProvider(loadCapacityValues: { _ in
            RuntimeStorageCapacityValues(
                total: 100,
                availableForImportantUsage: nil,
                available: nil
            )
        })

        XCTAssertEqual(provider.storageUsage(for: directory.path), RuntimeStorageUsageResult.unavailable)
    }

    func testStorageUsageUsesStandardAvailableCapacityWhenImportantCapacityIsMissing() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let provider = SystemRuntimeStorageUsageProvider(loadCapacityValues: { _ in
            RuntimeStorageCapacityValues(
                total: 100,
                availableForImportantUsage: nil,
                available: 40
            )
        })

        XCTAssertEqual(
            provider.storageUsage(for: directory.path),
            RuntimeStorageUsageResult.loaded(ResourceUsage(usedBytes: 60, totalBytes: 100))
        )
    }

    func testStorageUsageReportsResourceValueFailure() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let provider = SystemRuntimeStorageUsageProvider(loadCapacityValues: { _ in
            throw CocoaError(.fileReadNoPermission)
        })

        switch provider.storageUsage(for: directory.path) {
        case .failed(let message):
            XCTAssertFalse(message.isEmpty)
        case .loaded, .unavailable:
            XCTFail("Expected failed storage usage result")
        }
    }
}
