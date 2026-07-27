import Contracts
import Foundation
import OutboundAdapters
import XCTest

final class UpdateBootstrapHandoffAdaptersTests: XCTestCase {
    func testWriterCreatesExclusiveFixedInvocationDocument() throws {
        var events: [String] = []
        let writer = UpdateBootstrapHandoffInvocationWriter(
            operations: UpdateBootstrapHandoffInvocationWriteOperations(
                pathState: { url in
                    events.append("state:\(url.path)")
                    return .missing
                },
                createDirectory: { url, intermediate in
                    events.append("create:\(url.path):\(intermediate)")
                },
                writeData: { data, url, options in
                    events.append("write:\(url.path):\(options.contains(.atomic))")
                    let decoded = try JSONDecoder().decode(
                        UpdateBootstrapHandoffInvocation.self,
                        from: data
                    )
                    XCTAssertEqual(decoded, self.invocation())
                }
            )
        )

        let written = try writer.write(
            invocation(),
            stagedBundleRoot: URL(fileURLWithPath: "/updates/update-42")
        )

        XCTAssertEqual(
            written.url.path,
            "/updates/update-42/handoff/invocation.json"
        )
        XCTAssertEqual(events, [
            "state:/updates/update-42/handoff/invocation.json",
            "create:/updates/update-42/handoff:true",
            "write:/updates/update-42/handoff/invocation.json:true",
        ])
    }

    func testWriterNeverReplacesExistingInvocation() {
        var wrote = false
        let writer = UpdateBootstrapHandoffInvocationWriter(
            operations: UpdateBootstrapHandoffInvocationWriteOperations(
                pathState: { _ in .file },
                createDirectory: { _, _ in },
                writeData: { _, _, _ in wrote = true }
            )
        )

        XCTAssertThrowsError(try writer.write(
            invocation(),
            stagedBundleRoot: URL(fileURLWithPath: "/updates/update-42")
        )) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapHandoffInvocationWriteError,
                .destinationAlreadyExists(
                    path: "/updates/update-42/handoff/invocation.json",
                    state: "file"
                )
            )
        }
        XCTAssertFalse(wrote)
    }

    func testLauncherUsesOnlyFixedCommandAndInvocationArgument() throws {
        var command: (String, [String])?
        let launcher = UpdateBootstrapHandoffProcessLauncher(
            operations: UpdateBootstrapHandoffProcessLaunchOperations(
                fileState: { _ in .executable },
                run: { executable, arguments in
                    command = (executable, arguments)
                    return RuntimeProcessResult(
                        exitCode: 23,
                        stdout: "",
                        stderr: "next updater reported failure"
                    )
                }
            )
        )

        let result = try launcher.launch(
            invocation: invocation(),
            invocationURL: URL(
                fileURLWithPath: "/updates/update-42/handoff/invocation.json"
            ),
            stagedBundleRoot: URL(fileURLWithPath: "/updates/update-42")
        )

        XCTAssertEqual(result.exitCode, 23)
        XCTAssertEqual(command?.0, "/updates/update-42/updater/next-updater")
        XCTAssertEqual(command?.1, [
            "execute",
            "--invocation",
            "/updates/update-42/handoff/invocation.json",
        ])
    }

    func testLauncherDoesNotConvertProcessLaunchFailureToExitCode() {
        let launcher = UpdateBootstrapHandoffProcessLauncher(
            operations: UpdateBootstrapHandoffProcessLaunchOperations(
                fileState: { _ in .executable },
                run: { _, _ in
                    RuntimeProcessResult(
                        exitCode: 127,
                        stdout: "",
                        stderr: "permission denied",
                        executionIssue: RuntimeProcessExecutionIssue(
                            kind: .processLaunchFailed,
                            message: "permission denied"
                        )
                    )
                }
            )
        )

        XCTAssertThrowsError(try launcher.launch(
            invocation: invocation(),
            invocationURL: URL(
                fileURLWithPath: "/updates/update-42/handoff/invocation.json"
            ),
            stagedBundleRoot: URL(fileURLWithPath: "/updates/update-42")
        )) { error in
            XCTAssertEqual(
                error as? UpdateBootstrapHandoffProcessLaunchError,
                .processLaunchFailed(
                    path: "/updates/update-42/updater/next-updater",
                    reason: "permission denied"
                )
            )
        }
    }

    private func invocation() -> UpdateBootstrapHandoffInvocation {
        UpdateBootstrapHandoffInvocation(
            schemaVersion: "vitalserver.update-bootstrap-handoff/v1",
            updateId: "update-42",
            operationId: "operation-42",
            requestId: "request-42",
            bootstrapEnvelopeId: "envelope-42",
            bootstrapSignedSHA256: String(repeating: "a", count: 64),
            updateSpecificationSHA256: String(repeating: "b", count: 64),
            expectedJournalRevision: 3,
            updaterRelativePath: "updater/next-updater",
            specificationRelativePath: "spec/update.json",
            completionReceiptRelativePath: "handoff/completion-receipt.json"
        )
    }
}
