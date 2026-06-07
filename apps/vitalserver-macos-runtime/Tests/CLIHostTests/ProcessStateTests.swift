import Foundation
import Application
import Contracts
import OutboundAdapters
@testable import CLIHost
import XCTest
import Errors

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

    func testStopPreservesPidFileWhenSignalFailsForPermission() {
        let fileStore = RuntimeFileStoreSpy()
        let pidFile = URL(fileURLWithPath: "/runtime/run/vitalserver-vm.pid")
        fileStore.files[pidFile] = Data("123\n".utf8)

        XCTAssertThrowsError(try ProcessState.stop(
            pidFile: pidFile,
            fileStore: fileStore,
            signalProcess: { _, _ in -1 },
            signalErrorNumber: { EPERM }
        )) { error in
            guard case ProcessStateError.runtimeOperationFailed(let message) = error else {
                return XCTFail("Expected ProcessStateError.runtimeOperationFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("failed to stop pid 123"))
            XCTAssertTrue(message.contains("pid file preserved"))
        }
        XCTAssertEqual(fileStore.files[pidFile], Data("123\n".utf8))
        XCTAssertEqual(fileStore.removed, [])
    }

    func testStopRemovesPidFileOnlyWhenSignalReportsProcessMissing() throws {
        let fileStore = RuntimeFileStoreSpy()
        let pidFile = URL(fileURLWithPath: "/runtime/run/vitalserver-vm.pid")
        fileStore.files[pidFile] = Data("123\n".utf8)

        try ProcessState.stop(
            pidFile: pidFile,
            fileStore: fileStore,
            signalProcess: { _, _ in -1 },
            signalErrorNumber: { ESRCH }
        )

        XCTAssertNil(fileStore.files[pidFile])
        XCTAssertEqual(fileStore.removed, [pidFile])
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

    func testWaitUntilStoppedAfterServiceUnloadAllowsMissingPidFile() throws {
        let fileStore = RuntimeFileStoreSpy()
        let pidFile = URL(fileURLWithPath: "/runtime/run/vitalserver-vm.pid")
        var logs: [String] = []

        try ProcessState.waitUntilStoppedAfterServiceUnload(
            pidFile: pidFile,
            fileStore: fileStore,
            timeoutSeconds: 1,
            pollIntervalSeconds: 0.001,
            processExists: { _ in
                XCTFail("Missing pid file should not require process probing")
                return false
            },
            log: { logs.append($0) }
        )

        XCTAssertTrue(logs.contains {
            $0.contains("pid file is missing after VM service unload")
        })
    }

    func testInspectReportsRunningProcessState() {
        let fileStore = RuntimeFileStoreSpy()
        let pidFile = URL(fileURLWithPath: "/runtime/run/vitalserver-vm.pid")
        fileStore.files[pidFile] = Data("123\n".utf8)

        let state = ProcessState.inspect(
            pidFile: pidFile,
            fileStore: fileStore,
            processExists: { _ in true }
        )

        XCTAssertEqual(state, .running(pid: 123))
    }

    func testInspectKeepsInvalidPidDistinctFromMissingPidFile() {
        let fileStore = RuntimeFileStoreSpy()
        let pidFile = URL(fileURLWithPath: "/runtime/run/vitalserver-vm.pid")
        fileStore.files[pidFile] = Data("not-a-pid\n".utf8)

        let state = ProcessState.inspect(pidFile: pidFile, fileStore: fileStore)

        guard case .pidFileInvalid(let reason) = state else {
            return XCTFail("Expected pidFileInvalid, got \(state)")
        }
        XCTAssertTrue(reason.contains("invalid VM process pid file"))
    }

    func testInspectReportsPidFileInspectionFailureAsReadFailed() {
        let fileStore = RuntimeFileStoreSpy()
        let pidFile = URL(fileURLWithPath: "/runtime/run/vitalserver-vm.pid")
        fileStore.pathStates[pidFile.path] = .inspectFailed("permission denied")

        let state = ProcessState.inspect(pidFile: pidFile, fileStore: fileStore)

        guard case .readFailed(let reason) = state else {
            return XCTFail("Expected readFailed, got \(state)")
        }
        XCTAssertTrue(reason.contains("failed to inspect VM process pid file"))
        XCTAssertTrue(reason.contains("permission denied"))
    }

    func testInspectReportsPidFileDirectoryAsReadFailed() {
        let fileStore = RuntimeFileStoreSpy()
        let pidFile = URL(fileURLWithPath: "/runtime/run/vitalserver-vm.pid")
        fileStore.pathStates[pidFile.path] = .directory

        let state = ProcessState.inspect(pidFile: pidFile, fileStore: fileStore)

        guard case .readFailed(let reason) = state else {
            return XCTFail("Expected readFailed, got \(state)")
        }
        XCTAssertTrue(reason.contains("path state is unexpected"))
        XCTAssertTrue(reason.contains("state=directory"))
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

    func testRequestStopAndWaitFailsWhenPidFileIsMissing() {
        let fileStore = RuntimeFileStoreSpy()
        let pidFile = URL(fileURLWithPath: "/runtime/run/vitalserver-vm.pid")

        XCTAssertThrowsError(try ProcessState.requestStopAndWait(
            pidFile: pidFile,
            fileStore: fileStore,
            timeoutSeconds: 1,
            pollIntervalSeconds: 0.001,
            processExists: { _ in XCTFail("Missing pid file should fail before process probing"); return false },
            signalProcess: { _, _ in XCTFail("Missing pid file should fail before signaling"); return 0 }
        )) { error in
            guard case StopRuntimeVMProcessUseCaseError.runtimeOperationFailed(let message) = error else {
                return XCTFail("Expected StopRuntimeVMProcessUseCaseError.runtimeOperationFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("pid file is missing"))
        }
    }

    func testWaitUntilStoppedStateReportsStoppedWhenObservedPidExitsAfterPidFileDisappears() {
        let fileStore = RuntimeFileStoreSpy()
        let pidFile = URL(fileURLWithPath: "/runtime/run/vitalserver-vm.pid")
        fileStore.files[pidFile] = Data("123\n".utf8)
        var probeCount = 0

        let state = ProcessState.waitUntilStoppedState(
            pidFile: pidFile,
            fileStore: fileStore,
            timeoutSeconds: 1,
            pollIntervalSeconds: 0.001,
            processExists: { _ in
                probeCount += 1
                if probeCount == 1 {
                    fileStore.files.removeValue(forKey: pidFile)
                    return true
                }
                return false
            }
        )

        XCTAssertEqual(state, .stopped)
    }

    func testWaitUntilStoppedStateKeepsWaitingForOriginalPidWhenPidFileChanges() {
        let fileStore = RuntimeFileStoreSpy()
        let pidFile = URL(fileURLWithPath: "/runtime/run/vitalserver-vm.pid")
        fileStore.files[pidFile] = Data("123\n".utf8)
        var probes: [pid_t] = []
        var logs: [String] = []

        let state = ProcessState.waitUntilStoppedState(
            pidFile: pidFile,
            fileStore: fileStore,
            timeoutSeconds: 1,
            pollIntervalSeconds: 0.001,
            processExists: { pid in
                probes.append(pid)
                if probes.count == 1 {
                    fileStore.files[pidFile] = Data("456\n".utf8)
                    return true
                }
                return false
            },
            log: { logs.append($0) }
        )

        XCTAssertEqual(state, .stopped)
        XCTAssertEqual(probes, [123, 123])
        XCTAssertEqual(fileStore.files[pidFile], Data("456\n".utf8))
        XCTAssertTrue(logs.contains { $0.contains("pid file changed") && $0.contains("observedPid=123") && $0.contains("currentPid=456") })
    }

    func testRequestStopAndWaitKeepsWaitingForSignaledPidWhenPidFileChangesImmediately() throws {
        let fileStore = RuntimeFileStoreSpy()
        let pidFile = URL(fileURLWithPath: "/runtime/run/vitalserver-vm.pid")
        fileStore.files[pidFile] = Data("123\n".utf8)
        var probes: [pid_t] = []
        var signals: [(pid_t, Int32)] = []

        try ProcessState.requestStopAndWait(
            pidFile: pidFile,
            fileStore: fileStore,
            timeoutSeconds: 1,
            pollIntervalSeconds: 0.001,
            processExists: { pid in
                probes.append(pid)
                if probes.count == 1 {
                    return true
                }
                return false
            },
            signalProcess: { pid, signal in
                signals.append((pid, signal))
                fileStore.files[pidFile] = Data("456\n".utf8)
                return 0
            }
        )

        XCTAssertEqual(signals.count, 1)
        XCTAssertEqual(signals.first?.0, 123)
        XCTAssertEqual(signals.first?.1, SIGTERM)
        XCTAssertEqual(probes, [123, 123])
        XCTAssertEqual(fileStore.files[pidFile], Data("456\n".utf8))
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

    func testWaitUntilStoppedStateReportsTimeoutWithPid() {
        let fileStore = RuntimeFileStoreSpy()
        let pidFile = URL(fileURLWithPath: "/runtime/run/vitalserver-vm.pid")
        fileStore.files[pidFile] = Data("123\n".utf8)

        let state = ProcessState.waitUntilStoppedState(
            pidFile: pidFile,
            fileStore: fileStore,
            timeoutSeconds: 0,
            pollIntervalSeconds: 0.001,
            processExists: { _ in true }
        )

        XCTAssertEqual(state, .stopTimedOut(pid: 123, timeoutSeconds: 0))
    }

    func testWaitUntilStoppedStateUsesInjectedClockAndSleepForTimeout() {
        let fileStore = RuntimeFileStoreSpy()
        let pidFile = URL(fileURLWithPath: "/runtime/run/vitalserver-vm.pid")
        fileStore.files[pidFile] = Data("123\n".utf8)
        var currentTime = Date(timeIntervalSince1970: 0)
        var sleepIntervals: [TimeInterval] = []

        let state = ProcessState.waitUntilStoppedState(
            pidFile: pidFile,
            fileStore: fileStore,
            timeoutSeconds: 2,
            pollIntervalSeconds: 0.25,
            processExists: { _ in true },
            now: { currentTime },
            sleep: { interval in
                sleepIntervals.append(interval)
                currentTime = currentTime.addingTimeInterval(3)
            }
        )

        XCTAssertEqual(state, .stopTimedOut(pid: 123, timeoutSeconds: 2))
        XCTAssertEqual(sleepIntervals, [0.25])
    }

    func testWaitUntilStoppedStateReportsTimeoutWithOriginalPidWhenPidFileChanges() {
        let fileStore = RuntimeFileStoreSpy()
        let pidFile = URL(fileURLWithPath: "/runtime/run/vitalserver-vm.pid")
        fileStore.files[pidFile] = Data("123\n".utf8)

        let state = ProcessState.waitUntilStoppedState(
            pidFile: pidFile,
            fileStore: fileStore,
            timeoutSeconds: 0,
            pollIntervalSeconds: 0.001,
            processExists: { pid in
                fileStore.files[pidFile] = Data("456\n".utf8)
                return pid == 123
            }
        )

        XCTAssertEqual(state, .stopTimedOut(pid: 123, timeoutSeconds: 0))
    }

    func testRunningPidFailsWhenPidFileIsStale() {
        let fileStore = RuntimeFileStoreSpy()
        let pidFile = URL(fileURLWithPath: "/runtime/run/vitalserver-vm.pid")
        fileStore.files[pidFile] = Data("123\n".utf8)

        XCTAssertThrowsError(try ProcessState.runningPid(
            pidFile: pidFile,
            fileStore: fileStore,
            processExists: { _ in false }
        )) { error in
            guard case ProcessStateError.runtimeOperationFailed(let message) = error else {
                return XCTFail("Expected ProcessStateError.runtimeOperationFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("stale"))
            XCTAssertTrue(message.contains("123"))
        }
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
            guard case StopRuntimeVMProcessUseCaseError.runtimeOperationFailed(let message) = error else {
                return XCTFail("Expected StopRuntimeVMProcessUseCaseError.runtimeOperationFailed, got \(error)")
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
            guard case StopRuntimeVMProcessUseCaseError.runtimeOperationFailed(let message) = error else {
                return XCTFail("Expected StopRuntimeVMProcessUseCaseError.runtimeOperationFailed, got \(error)")
            }
            XCTAssertTrue(message.contains("invalid VM process pid file"))
        }
    }
}

private extension ProcessState {
    static func waitUntilStopped(
        pidFile: URL,
        fileStore: RuntimeFileReading & RuntimeFileWriting,
        timeoutSeconds: TimeInterval,
        pollIntervalSeconds: TimeInterval,
        processExists: @escaping (pid_t) -> Bool = ProcessState.defaultProcessExists,
        now: @escaping () -> Date = Date.init,
        sleep: @escaping (TimeInterval) -> Void = { _ in },
        log: @escaping (String) -> Void = { _ in }
    ) throws {
        try StopRuntimeVMProcessUseCase().waitUntilStopped(
            timeoutSeconds: timeoutSeconds,
            pollIntervalSeconds: pollIntervalSeconds,
            operations: stopOperations(
                pidFile: pidFile,
                fileStore: fileStore,
                processExists: processExists,
                now: now,
                sleep: sleep,
                log: log
            )
        )
    }

    static func waitUntilStoppedAfterServiceUnload(
        pidFile: URL,
        fileStore: RuntimeFileReading & RuntimeFileWriting,
        timeoutSeconds: TimeInterval,
        pollIntervalSeconds: TimeInterval,
        processExists: @escaping (pid_t) -> Bool = ProcessState.defaultProcessExists,
        now: @escaping () -> Date = Date.init,
        sleep: @escaping (TimeInterval) -> Void = { _ in },
        log: @escaping (String) -> Void = { _ in }
    ) throws {
        try StopRuntimeVMProcessUseCase().waitUntilStopped(
            timeoutSeconds: timeoutSeconds,
            pollIntervalSeconds: pollIntervalSeconds,
            allowMissingPidFile: true,
            operations: stopOperations(
                pidFile: pidFile,
                fileStore: fileStore,
                processExists: processExists,
                now: now,
                sleep: sleep,
                log: log
            )
        )
    }

    static func waitUntilStoppedState(
        pidFile: URL,
        fileStore: RuntimeFileReading & RuntimeFileWriting,
        timeoutSeconds: TimeInterval,
        pollIntervalSeconds: TimeInterval,
        processExists: @escaping (pid_t) -> Bool = ProcessState.defaultProcessExists,
        now: @escaping () -> Date = Date.init,
        sleep: @escaping (TimeInterval) -> Void = { _ in },
        log: @escaping (String) -> Void = { _ in }
    ) -> RuntimeVMProcessState {
        StopRuntimeVMProcessUseCase().waitUntilStoppedState(
            timeoutSeconds: timeoutSeconds,
            pollIntervalSeconds: pollIntervalSeconds,
            operations: stopOperations(
                pidFile: pidFile,
                fileStore: fileStore,
                processExists: processExists,
                now: now,
                sleep: sleep,
                log: log
            )
        )
    }

    static func requestStopAndWait(
        pidFile: URL,
        fileStore: RuntimeFileReading & RuntimeFileWriting,
        timeoutSeconds: TimeInterval,
        pollIntervalSeconds: TimeInterval,
        processExists: @escaping (pid_t) -> Bool = ProcessState.defaultProcessExists,
        signalProcess: @escaping (pid_t, Int32) -> Int32 = { _, _ in 0 },
        now: @escaping () -> Date = Date.init,
        sleep: @escaping (TimeInterval) -> Void = { _ in },
        log: @escaping (String) -> Void = { _ in }
    ) throws {
        try StopRuntimeVMProcessUseCase().requestStopAndWait(
            terminateSignal: SIGTERM,
            noSuchProcessErrorNumber: Int32(ESRCH),
            timeoutSeconds: timeoutSeconds,
            pollIntervalSeconds: pollIntervalSeconds,
            operations: stopOperations(
                pidFile: pidFile,
                fileStore: fileStore,
                processExists: processExists,
                signalProcess: signalProcess,
                now: now,
                sleep: sleep,
                log: log
            )
        )
    }

    static func forceKillAndWait(
        pidFile: URL,
        fileStore: RuntimeFileReading & RuntimeFileWriting,
        timeoutSeconds: TimeInterval,
        pollIntervalSeconds: TimeInterval,
        processExists: @escaping (pid_t) -> Bool = ProcessState.defaultProcessExists,
        signalProcess: @escaping (pid_t, Int32) -> Int32 = { _, _ in 0 },
        now: @escaping () -> Date = Date.init,
        sleep: @escaping (TimeInterval) -> Void = { _ in },
        log: @escaping (String) -> Void = { _ in }
    ) throws {
        try StopRuntimeVMProcessUseCase().forceKillAndWait(
            killSignal: SIGKILL,
            noSuchProcessErrorNumber: Int32(ESRCH),
            timeoutSeconds: timeoutSeconds,
            pollIntervalSeconds: pollIntervalSeconds,
            operations: stopOperations(
                pidFile: pidFile,
                fileStore: fileStore,
                processExists: processExists,
                signalProcess: signalProcess,
                now: now,
                sleep: sleep,
                log: log
            )
        )
    }
}
