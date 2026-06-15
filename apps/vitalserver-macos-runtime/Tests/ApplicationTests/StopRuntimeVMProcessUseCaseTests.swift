import Application
import Contracts
import XCTest

final class StopRuntimeVMProcessUseCaseTests: XCTestCase {
    func testRequestStopBlocksMissingPidFileBeforeProbingOrSignaling() {
        var probedPids: [Int32] = []
        var signaled: [(Int32, Int32)] = []
        let operations = makeOperations(
            readPid: { .missing },
            processExists: { pid in
                probedPids.append(pid)
                return false
            },
            signalProcess: { pid, signal in
                signaled.append((pid, signal))
                return 0
            }
        )

        XCTAssertThrowsError(try StopRuntimeVMProcessUseCase().requestStopAndWait(
            terminateSignal: 15,
            noSuchProcessErrorNumber: 3,
            timeoutSeconds: 1,
            pollIntervalSeconds: 0.1,
            operations: operations
        )) { error in
            XCTAssertEqual(
                error as? StopRuntimeVMProcessUseCaseError,
                .runtimeOperationFailed("VM process pid file is missing; process stop state is not proven")
            )
        }
        XCTAssertTrue(probedPids.isEmpty)
        XCTAssertTrue(signaled.isEmpty)
    }

    func testRequestStopKeepsWaitingForOriginalPidWhenPidFileChangesAfterSignal() throws {
        var pidReadCount = 0
        var probedPids: [Int32] = []
        var removedExpectedPids: [Int32] = []
        let operations = makeOperations(
            readPid: {
                pidReadCount += 1
                return pidReadCount == 1 ? .loaded(123) : .loaded(456)
            },
            processExists: { pid in
                probedPids.append(pid)
                return probedPids.count == 1
            },
            signalProcess: { _, _ in 0 },
            removePidFileIfStillReferences: { removedExpectedPids.append($0) }
        )

        try StopRuntimeVMProcessUseCase().requestStopAndWait(
            terminateSignal: 15,
            noSuchProcessErrorNumber: 3,
            timeoutSeconds: 1,
            pollIntervalSeconds: 0.1,
            operations: operations
        )

        XCTAssertEqual(probedPids, [123, 123])
        XCTAssertEqual(removedExpectedPids, [123])
    }

    func testSignalFailurePreservesErrnoAndDoesNotRemovePidFile() {
        var removeCount = 0
        let operations = makeOperations(
            readPid: { .loaded(123) },
            processExists: { _ in true },
            signalProcess: { _, _ in -1 },
            signalErrorNumber: { 1 },
            removePidFile: { removeCount += 1 },
            removePidFileIfStillReferences: { _ in removeCount += 1 }
        )

        let state = StopRuntimeVMProcessUseCase().requestStopAndWaitState(
            terminateSignal: 15,
            noSuchProcessErrorNumber: 3,
            timeoutSeconds: 1,
            pollIntervalSeconds: 0.1,
            operations: operations
        )

        XCTAssertEqual(state, .signalFailed(pid: 123, signal: 15, errnoCode: 1))
        XCTAssertEqual(removeCount, 0)
    }

    func testForceKillTreatsNoSuchProcessAsStalePidAndRemovesOnlyMatchingPidFile() {
        var removedExpectedPids: [Int32] = []
        let operations = makeOperations(
            readPid: { .loaded(123) },
            processExists: { _ in true },
            signalProcess: { _, _ in -1 },
            signalErrorNumber: { 3 },
            removePidFileIfStillReferences: { removedExpectedPids.append($0) }
        )

        let state = StopRuntimeVMProcessUseCase().forceKillAndWaitState(
            killSignal: 9,
            noSuchProcessErrorNumber: 3,
            timeoutSeconds: 1,
            pollIntervalSeconds: 0.1,
            operations: operations
        )

        XCTAssertEqual(state, .stalePid(pid: 123))
        XCTAssertEqual(removedExpectedPids, [123])
    }

    private func makeOperations(
        readPid: @escaping () -> RuntimePidFileReadResult = { .loaded(123) },
        processExists: @escaping (Int32) -> Bool = { _ in false },
        signalProcess: @escaping (Int32, Int32) -> Int32 = { _, _ in 0 },
        signalErrorNumber: @escaping () -> Int32 = { 0 },
        removePidFile: @escaping () -> Void = {},
        removePidFileIfStillReferences: @escaping (Int32) -> Void = { _ in },
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 0) },
        sleep: @escaping (TimeInterval) -> Void = { _ in },
        log: @escaping (String) -> Void = { _ in }
    ) -> StopRuntimeVMProcessOperations {
        StopRuntimeVMProcessOperations(
            readPid: readPid,
            processExists: processExists,
            sendSignal: signalProcess,
            signalErrorNumber: signalErrorNumber,
            removePidFile: removePidFile,
            removePidFileIfStillReferences: removePidFileIfStillReferences,
            now: now,
            sleep: sleep,
            log: log
        )
    }
}
