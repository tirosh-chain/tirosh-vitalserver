import Contracts
import Foundation
import OutboundAdapters
import XCTest

final class ImmutableUpdateBootstrapStagerTests: XCTestCase {
    func testStageCopiesToAttemptPathThenAtomicallyMovesToUpdatePath() throws {
        let harness = StagingHarness()
        let staged = try harness.stager.stage(harness.input)

        XCTAssertEqual(staged.root.path, "/updates/update-42")
        XCTAssertEqual(harness.events, [
            "state:/source/bundle",
            "state:/updates/update-42",
            "state:/updates/.update-42.staging-attempt-7",
            "create:/updates:true",
            "copy:/source/bundle->/updates/.update-42.staging-attempt-7",
            "move:/updates/.update-42.staging-attempt-7->/updates/update-42",
        ])
    }

    func testStageDoesNotReplaceAnExistingFinalDestination() {
        let harness = StagingHarness(states: [
            "/updates/update-42": .directory,
        ])

        XCTAssertThrowsError(try harness.stager.stage(harness.input)) { error in
            XCTAssertEqual(
                error as? ImmutableUpdateBootstrapStagingError,
                .destinationAlreadyExists(
                    path: "/updates/update-42",
                    state: "directory"
                )
            )
        }
        XCTAssertFalse(harness.events.contains { $0.hasPrefix("copy:") })
        XCTAssertFalse(harness.events.contains { $0.hasPrefix("remove:") })
    }

    func testStageRejectsPathTraversalIdentifierBeforeReadingFilesystem() {
        let harness = StagingHarness()
        let input = UpdateBootstrapStagingInput(
            updateId: "../update-42",
            stagingAttemptId: "attempt-7",
            sourceBundle: URL(fileURLWithPath: "/source/bundle")
        )

        XCTAssertThrowsError(try harness.stager.stage(input)) { error in
            XCTAssertEqual(
                error as? ImmutableUpdateBootstrapStagingError,
                .invalidIdentifier(field: "updateId", value: "../update-42")
            )
        }
        XCTAssertEqual(harness.events, [])
    }

    func testStageRemovesOnlyItsTemporaryAttemptWhenCopyFails() {
        let temporary = "/updates/.update-42.staging-attempt-7"
        let harness = StagingHarness(
            copyError: TestStagingError.copyFailed,
            temporaryStateAfterCopyFailure: .directory
        )

        XCTAssertThrowsError(try harness.stager.stage(harness.input)) { error in
            XCTAssertEqual(
                error as? ImmutableUpdateBootstrapStagingError,
                .stagingFailed(reason: "copyFailed")
            )
        }
        XCTAssertTrue(harness.events.contains("remove:\(temporary)"))
        XCTAssertFalse(harness.events.contains("remove:/updates/update-42"))
    }

    func testStagePreservesPrimaryAndCleanupFailures() {
        let harness = StagingHarness(
            copyError: TestStagingError.copyFailed,
            removeError: TestStagingError.cleanupFailed,
            temporaryStateAfterCopyFailure: .directory
        )

        XCTAssertThrowsError(try harness.stager.stage(harness.input)) { error in
            XCTAssertEqual(
                error as? ImmutableUpdateBootstrapStagingError,
                .stagingFailedAndCleanupFailed(
                    stagingReason: "copyFailed",
                    cleanupReason: "cleanupFailed"
                )
            )
        }
    }
}

private enum TestStagingError: Error {
    case copyFailed
    case cleanupFailed
}

private final class StagingHarness {
    let input = UpdateBootstrapStagingInput(
        updateId: "update-42",
        stagingAttemptId: "attempt-7",
        sourceBundle: URL(fileURLWithPath: "/source/bundle")
    )
    var events: [String] = []

    private var states: [String: RuntimePathState]
    private let copyError: Error?
    private let removeError: Error?
    private let temporaryStateAfterCopyFailure: RuntimePathState?
    private var copyAttempted = false

    init(
        states: [String: RuntimePathState] = [:],
        copyError: Error? = nil,
        removeError: Error? = nil,
        temporaryStateAfterCopyFailure: RuntimePathState? = nil
    ) {
        self.states = states
        self.copyError = copyError
        self.removeError = removeError
        self.temporaryStateAfterCopyFailure = temporaryStateAfterCopyFailure
    }

    lazy var stager = ImmutableUpdateBootstrapStager(
        stagingRoot: URL(fileURLWithPath: "/updates"),
        operations: ImmutableUpdateBootstrapStagingOperations(
            pathState: { [self] url in
                events.append("state:\(url.path)")
                if url.path == input.sourceBundle.path {
                    return .directory
                }
                if copyAttempted,
                   url.path == "/updates/.update-42.staging-attempt-7",
                   let temporaryStateAfterCopyFailure {
                    return temporaryStateAfterCopyFailure
                }
                return states[url.path] ?? .missing
            },
            createDirectory: { [self] url, intermediate in
                events.append("create:\(url.path):\(intermediate)")
            },
            copyItem: { [self] source, destination in
                events.append("copy:\(source.path)->\(destination.path)")
                copyAttempted = true
                if let copyError {
                    throw copyError
                }
            },
            moveItem: { [self] source, destination in
                events.append("move:\(source.path)->\(destination.path)")
            },
            removeItem: { [self] url in
                events.append("remove:\(url.path)")
                if let removeError {
                    throw removeError
                }
            }
        )
    )
}
