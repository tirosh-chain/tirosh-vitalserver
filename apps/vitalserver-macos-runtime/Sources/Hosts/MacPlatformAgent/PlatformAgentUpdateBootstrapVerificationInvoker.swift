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

    public init(
        installedPaths: InstalledRuntimePaths = .defaultInstalled,
        clock: any RuntimeClock = SystemRuntimeClock(),
        generateInvocationId: @escaping @Sendable () -> String = {
            UUID().uuidString.lowercased()
        },
        fileStore: RuntimeFileStore = SystemRuntimeFileStore()
    ) {
        self.installedPaths = installedPaths
        self.clock = clock
        self.generateInvocationId = generateInvocationId
        self.fileStore = fileStore
    }

    public func invoke(
        bundleURL: URL,
        spawn: @escaping @Sendable (String) async -> RuntimeCommandResult
    ) async -> RuntimeCommandResult {
        let invocationId = generateInvocationId()
        let spawned = SpawnCapture()
        do {
            _ = try await InvokePlatformAgentUpdateBootstrapVerificationUseCase()
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
}

private final class SpawnCapture: @unchecked Sendable {
    var result: RuntimeCommandResult?
}
