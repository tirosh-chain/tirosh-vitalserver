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

    func testRemovePidFileLogsRemovalFailure() {
        let fileStore = RuntimeFileStoreSpy()
        let pidFile = URL(fileURLWithPath: "/runtime/run/vitalserver-vm.pid")
        fileStore.files[pidFile] = Data("123\n".utf8)
        fileStore.removeItemError = CocoaError(.fileWriteNoPermission)
        var logs: [String] = []

        ProcessState.removePidFile(pidFile, fileStore: fileStore, log: { logs.append($0) })

        XCTAssertEqual(fileStore.files[pidFile], Data("123\n".utf8))
        XCTAssertTrue(logs.contains { $0.contains("failed to remove VM process pid file") })
        XCTAssertTrue(logs.contains { $0.contains(pidFile.path) })
    }

    func testWaitUntilStoppedLogsStalePidRemovalFailure() throws {
        let fileStore = RuntimeFileStoreSpy()
        let pidFile = URL(fileURLWithPath: "/runtime/run/vitalserver-vm.pid")
        fileStore.files[pidFile] = Data("123\n".utf8)
        fileStore.removeItemError = CocoaError(.fileWriteNoPermission)
        var logs: [String] = []

        try ProcessState.waitUntilStopped(
            pidFile: pidFile,
            fileStore: fileStore,
            timeoutSeconds: 1,
            pollIntervalSeconds: 0.001,
            processExists: { _ in false },
            log: { logs.append($0) }
        )

        XCTAssertTrue(logs.contains { $0.contains("failed to remove VM process pid file") })
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

    func testRequestStopAndWaitSignalsProcessAndWaitsUntilStopped() throws {
        let fileStore = RuntimeFileStoreSpy()
        let pidFile = URL(fileURLWithPath: "/runtime/run/vitalserver-vm.pid")
        fileStore.files[pidFile] = Data("123\n".utf8)
        var processIsRunning = true
        var signals: [(pid_t, Int32)] = []

        try ProcessState.requestStopAndWait(
            pidFile: pidFile,
            fileStore: fileStore,
            timeoutSeconds: 1,
            pollIntervalSeconds: 0.001,
            processExists: { _ in processIsRunning },
            signalProcess: { pid, signal in
                signals.append((pid, signal))
                processIsRunning = false
                return 0
            }
        )

        XCTAssertEqual(signals.count, 1)
        XCTAssertEqual(signals.first?.0, 123)
        XCTAssertEqual(signals.first?.1, SIGTERM)
        XCTAssertNil(fileStore.files[pidFile])
    }

    func testForceKillAndWaitSignalsProcessAndWaitsUntilStopped() throws {
        let fileStore = RuntimeFileStoreSpy()
        let pidFile = URL(fileURLWithPath: "/runtime/run/vitalserver-vm.pid")
        fileStore.files[pidFile] = Data("123\n".utf8)
        var processIsRunning = true
        var signals: [(pid_t, Int32)] = []

        try ProcessState.forceKillAndWait(
            pidFile: pidFile,
            fileStore: fileStore,
            timeoutSeconds: 1,
            pollIntervalSeconds: 0.001,
            processExists: { _ in processIsRunning },
            signalProcess: { pid, signal in
                signals.append((pid, signal))
                processIsRunning = false
                return 0
            }
        )

        XCTAssertEqual(signals.count, 1)
        XCTAssertEqual(signals.first?.0, 123)
        XCTAssertEqual(signals.first?.1, SIGKILL)
        XCTAssertNil(fileStore.files[pidFile])
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

    func testWaitUntilStoppedFailsWhenPidFileIsInvalid() {
        let fileStore = RuntimeFileStoreSpy()
        let pidFile = URL(fileURLWithPath: "/runtime/run/vitalserver-vm.pid")
        fileStore.files[pidFile] = Data("not-a-pid\n".utf8)

        XCTAssertThrowsError(try ProcessState.waitUntilStopped(
            pidFile: pidFile,
            fileStore: fileStore,
            timeoutSeconds: 1,
            pollIntervalSeconds: 0.001,
            processExists: { _ in false }
        )) { error in
            guard case LauncherError.runtimeOperationFailed(let message) = error else {
                return XCTFail("Expected runtimeOperationFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("invalid VM process pid file"))
        }
    }

    func testRequestStopAndWaitFailsWhenPidFileIsInvalid() {
        let fileStore = RuntimeFileStoreSpy()
        let pidFile = URL(fileURLWithPath: "/runtime/run/vitalserver-vm.pid")
        fileStore.files[pidFile] = Data("not-a-pid\n".utf8)

        XCTAssertThrowsError(try ProcessState.requestStopAndWait(
            pidFile: pidFile,
            fileStore: fileStore,
            timeoutSeconds: 1,
            pollIntervalSeconds: 0.001,
            processExists: { _ in false },
            signalProcess: { _, _ in XCTFail("Invalid pid file should fail before signaling"); return 0 }
        )) { error in
            guard case LauncherError.runtimeOperationFailed(let message) = error else {
                return XCTFail("Expected runtimeOperationFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("invalid VM process pid file"))
        }
    }
}
