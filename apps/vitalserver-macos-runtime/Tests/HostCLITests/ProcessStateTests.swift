import Foundation
@testable import HostCLI
import XCTest

final class ProcessStateTests: XCTestCase {
    func testWriteCurrentPidCreatesParentDirectoryAndWritesPidFile() throws {
        let fileStore = RuntimeFileStoreSpy()
        let pidFile = URL(fileURLWithPath: "/runtime/run/vitalserver-vm.pid")

        try ProcessState.writeCurrentPid(pidFile: pidFile, fileStore: fileStore)

        XCTAssertTrue(fileStore.directories.contains { $0.path == "/runtime/run" })
        let text = String(decoding: try XCTUnwrap(fileStore.files[pidFile]), as: UTF8.self)
        XCTAssertEqual(text, "\(getpid())\n")
    }

    func testRemovePidFileUsesFileStore() {
        let fileStore = RuntimeFileStoreSpy()
        let pidFile = URL(fileURLWithPath: "/runtime/run/vitalserver-vm.pid")
        fileStore.files[pidFile] = Data("123\n".utf8)

        ProcessState.removePidFile(pidFile, fileStore: fileStore)

        XCTAssertNil(fileStore.files[pidFile])
        XCTAssertEqual(fileStore.removed, [pidFile])
    }

    func testWaitUntilStoppedRemovesStalePidFile() throws {
        let fileStore = RuntimeFileStoreSpy()
        let pidFile = URL(fileURLWithPath: "/runtime/run/vitalserver-vm.pid")
        fileStore.files[pidFile] = Data("123\n".utf8)

        try ProcessState.waitUntilStopped(
            pidFile: pidFile,
            fileStore: fileStore,
            timeoutSeconds: 1,
            pollIntervalSeconds: 0.001,
            processExists: { _ in false }
        )

        XCTAssertNil(fileStore.files[pidFile])
        XCTAssertEqual(fileStore.removed, [pidFile])
    }

    func testWaitUntilStoppedTimesOutWhenProcessStillExists() {
        let fileStore = RuntimeFileStoreSpy()
        let pidFile = URL(fileURLWithPath: "/runtime/run/vitalserver-vm.pid")
        fileStore.files[pidFile] = Data("123\n".utf8)

        XCTAssertThrowsError(try ProcessState.waitUntilStopped(
            pidFile: pidFile,
            fileStore: fileStore,
            timeoutSeconds: 0,
            pollIntervalSeconds: 0.001,
            processExists: { _ in true }
        ))
    }
}
