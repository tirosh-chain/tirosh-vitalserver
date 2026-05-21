import RuntimeCore
import XCTest

final class LocalRuntimeFileStoreTests: XCTestCase {
    func testFileAndDirectoryExistenceAreDistinct() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let file = directory.appendingPathComponent("value.txt")
        let store = LocalRuntimeFileStore()

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
        let store = LocalRuntimeFileStore()

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: file)

        XCTAssertEqual(try store.readUTF8Text(file), "hello")
        XCTAssertEqual(try store.readData(file), Data("hello".utf8))

        try FileManager.default.removeItem(at: directory)
    }

    func testWritesCopiesMovesListsAndRemovesFiles() throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let source = directory.appendingPathComponent("source.txt")
        let copy = directory.appendingPathComponent("copy.txt")
        let moved = directory.appendingPathComponent("moved.txt")
        let store = LocalRuntimeFileStore()

        try store.createDirectory(at: directory, withIntermediateDirectories: true)
        try store.writeData(Data("payload".utf8), to: source, options: [])
        try store.copyItem(at: source, to: copy)
        try store.moveItem(at: copy, to: moved)

        let names = try store.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil,
            options: []
        ).map(\.lastPathComponent)

        XCTAssertTrue(names.contains("source.txt"))
        XCTAssertTrue(names.contains("moved.txt"))
        XCTAssertEqual(try store.readUTF8Text(moved), "payload")

        try store.removeItem(at: moved)
        XCTAssertFalse(store.fileExists(moved))

        try FileManager.default.removeItem(at: directory)
    }
}
