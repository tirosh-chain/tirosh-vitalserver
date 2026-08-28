import Application
import Contracts
import Domain
import Foundation
import OutboundAdapters
import RuntimeControl

public struct SystemPlatformAgentUpdateBootstrapVerificationInvoker:
    PlatformAgentUpdateBootstrapVerificationInvoking,
    @unchecked Sendable
{
    private let installedPaths: InstalledRuntimePaths
    private let clock: any RuntimeClock
    private let generateInvocationId: @Sendable () -> String
    private let fileStore: RuntimeFileStore
    private let selectionOwner: (any PlatformAgentUpdateBootstrapSelectionOwning)?

    public init(
        installedPaths: InstalledRuntimePaths = .defaultInstalled,
        clock: any RuntimeClock = SystemRuntimeClock(),
        generateInvocationId: @escaping @Sendable () -> String = {
            UUID().uuidString.lowercased()
        },
        fileStore: RuntimeFileStore = SystemRuntimeFileStore(),
        selectionOwner: (any PlatformAgentUpdateBootstrapSelectionOwning)? = nil
    ) {
        self.installedPaths = installedPaths
        self.clock = clock
        self.generateInvocationId = generateInvocationId
        self.fileStore = fileStore
        self.selectionOwner = selectionOwner
    }

    public func invoke(
        bundleURL: URL,
        spawn: @escaping @Sendable (String) async -> RuntimeCommandResult
    ) async -> RuntimeCommandResult {
        let invocationId = generateInvocationId()
        let spawned = SpawnCapture()
        do {
            let outcome = try await InvokePlatformAgentUpdateBootstrapVerificationUseCase()
                .invoke(
                    verificationInvocationId: invocationId,
                    bundlePath: bundleURL.path,
                    observedAt: UpdateBootstrapCanonicalTimestampSyntax.format(
                        clock.now
                    ),
                    persist: { evidence in
                        try PlatformAgentUpdateBootstrapVerificationEvidenceWriter(
                            operations:
                                PlatformAgentUpdateBootstrapVerificationEvidenceWriteOperations(
                                    pathState: fileStore.pathState,
                                    createDirectory: fileStore.createDirectory,
                                    writeData: { data, url, options in
                                        try fileStore.writeData(
                                            data,
                                            to: url,
                                            options: options
                                        )
                                    },
                                    validate:
                                        PlatformAgentUpdateBootstrapVerificationPolicy
                                        .validate
                                )
                        ).write(
                            evidence,
                            to: installedPaths
                                .platformAgentUpdateBootstrapVerificationEvidence(
                                    verificationInvocationId:
                                        evidence.verificationInvocationId
                                )
                        )
                    },
                    spawn: { id in
                        let result = await spawn(id)
                        spawned.result = result
                        if let issue = result.executionIssue {
                            return .spawnFailed(reason: issue.message)
                        }
                        return .completed(exitCode: result.exitCode)
                    },
                    bindingRead: { id in
                        UpdateBootstrapVerificationInvocationBindingReader(
                            pathState: fileStore.pathState,
                            readData: fileStore.readData
                        ).read(
                            at: installedPaths
                                .updateBootstrapVerificationInvocationBinding(
                                    verificationInvocationId: id
                                )
                        )
                    }
                )
            if case .succeeded(let updateId, let digest) = outcome,
               let selectionOwner
            {
                try selectionOwner.recordVerifiedSelection(
                    verificationInvocationId: invocationId,
                    updateId: updateId,
                    canonicalPayloadSHA256: digest,
                    observedBundlePath: bundleURL.path,
                    observedAt: UpdateBootstrapCanonicalTimestampSyntax.format(
                        clock.now
                    )
                )
            }
        } catch {
            return PlatformAgentVerificationPersistFailureMapping.commandResult(
                error: error,
                spawned: spawned.result
            )
        }
        return spawned.result ?? RuntimeCommandResult(
            exitCode: 1,
            stdout: "",
            stderr: "platform-agent verification spawn did not run",
            executionIssue: nil
        )
    }
}

enum PlatformAgentVerificationPersistFailureMapping {
    static func commandResult(
        error: Error,
        spawned: RuntimeCommandResult?
    ) -> RuntimeCommandResult {
        if let spawned {
            var issues = spawned.outputIssues
            var exitCode = spawned.exitCode
            if isEvidencePersistFailed(error) {
                issues.append(
                    RuntimeCommandOutputIssue(
                        stream: .stderr,
                        message:
                            "platform-agent verification evidence persist failed: \(error)"
                    )
                )
                if spawned.exitCode == 0 {
                    exitCode = 1
                }
            } else if let recordError = selectionRecordError(error) {
                issues.append(
                    RuntimeCommandOutputIssue(
                        stream: .stderr,
                        message: selectionRecordMessage(recordError)
                    )
                )
                if spawned.exitCode == 0 {
                    exitCode = 1
                }
            }
            return RuntimeCommandResult(
                exitCode: exitCode,
                stdout: spawned.stdout,
                stderr: spawned.stderr,
                outputIssues: issues,
                executionIssue: spawned.executionIssue
            )
        }
        let stderr: String
        if isEvidencePersistFailed(error) {
            stderr =
                "platform-agent verification evidence persist failed: \(error)"
        } else if let recordError = selectionRecordError(error) {
            stderr = selectionRecordMessage(recordError)
        } else {
            stderr = String(describing: error)
        }
        return RuntimeCommandResult(
            exitCode: 1,
            stdout: "",
            stderr: stderr,
            executionIssue: nil
        )
    }

    private static func isEvidencePersistFailed(_ error: Error) -> Bool {
        guard let error =
            error as? InvokePlatformAgentUpdateBootstrapVerificationError else {
            return false
        }
        if case .evidencePersistFailed = error {
            return true
        }
        return false
    }

    private static func selectionRecordError(
        _ error: Error
    ) -> RecordPlatformAgentUpdateBootstrapVerifiedSelectionError? {
        error as? RecordPlatformAgentUpdateBootstrapVerifiedSelectionError
    }

    private static func selectionRecordMessage(
        _ error: RecordPlatformAgentUpdateBootstrapVerifiedSelectionError
    ) -> String {
        switch error {
        case .persistFailed(let reason):
            return
                "platform-agent verified selection persist failed: \(reason)"
        case .inFlight(let requestId):
            return
                "platform-agent verified selection in flight requestId=\(requestId)"
        case .inspectionFailed(let path, let reason):
            return
                "platform-agent verified selection inspection failed path=\(path) reason=\(reason)"
        case .permissionDenied(let path, let reason):
            return
                "platform-agent verified selection permission denied path=\(path) reason=\(reason)"
        case .readFailed(let path, let reason):
            return
                "platform-agent verified selection read failed path=\(path) reason=\(reason)"
        case .decodeFailed(let path, let reason):
            return
                "platform-agent verified selection decode failed path=\(path) reason=\(reason)"
        case .unexpectedPathState(let path, let state):
            return
                "platform-agent verified selection unexpected path state path=\(path) state=\(state)"
        case .missing(let path):
            return "platform-agent verified selection missing: \(path)"
        case .invalidSelectionId(let value):
            return "platform-agent verified selection invalidSelectionId: \(value)"
        case .invalidVerificationInvocationId(let value):
            return
                "platform-agent verified selection invalidVerificationInvocationId: \(value)"
        case .invalidUpdateId(let value):
            return "platform-agent verified selection invalidUpdateId: \(value)"
        case .invalidCanonicalPayloadSHA256(let value):
            return
                "platform-agent verified selection invalidCanonicalPayloadSHA256: \(value)"
        case .invalidObservedBundlePath(let value):
            return
                "platform-agent verified selection invalidObservedBundlePath: \(value)"
        case .invalidObservedAt(let value):
            return
                "platform-agent verified selection invalidObservedAt: \(value)"
        case .invalid(let reason):
            return "platform-agent verified selection invalid: \(reason)"
        }
    }
}

private final class SpawnCapture: @unchecked Sendable {
    var result: RuntimeCommandResult?
}
