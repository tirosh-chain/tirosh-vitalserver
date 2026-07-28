import Contracts
import Foundation

public enum DurableUpdateBootstrapHandoffLaunchError:
    Error, Equatable, Sendable {
    case updaterUnavailable(path: String)
    case updaterNotExecutable(path: String)
    case updaterInspectionFailed(path: String, reason: String)
    case updaterStateUnknown(path: String, state: String)
    case terminalCompletionMissing(jobId: String, state: UpdateHandoffJobState)
    case terminalOutcomeMismatch(
        jobId: String,
        state: UpdateHandoffJobState,
        outcome: UpdateHandoffCompletionOutcome
    )
    case succeededWithoutZeroExitCode(jobId: String, exitCode: Int32?)
}

public struct DurableUpdateBootstrapHandoffLaunchOperations {
    public let fileState: (URL) -> RuntimeFileState
    public let submit: (
        String,
        UpdateBootstrapHandoffInvocation,
        URL,
        URL
    ) throws -> UpdateHandoffJobDocument
    public let startSupervisor: () throws -> Void
    public let waitForTerminal: (String) throws -> UpdateHandoffJobDocument

    public init(
        fileState: @escaping (URL) -> RuntimeFileState,
        submit: @escaping (
            String,
            UpdateBootstrapHandoffInvocation,
            URL,
            URL
        ) throws -> UpdateHandoffJobDocument,
        startSupervisor: @escaping () throws -> Void,
        waitForTerminal: @escaping (
            String
        ) throws -> UpdateHandoffJobDocument
    ) {
        self.fileState = fileState
        self.submit = submit
        self.startSupervisor = startSupervisor
        self.waitForTerminal = waitForTerminal
    }
}

public struct DurableUpdateBootstrapHandoffLauncher {
    public let operations: DurableUpdateBootstrapHandoffLaunchOperations

    public init(operations: DurableUpdateBootstrapHandoffLaunchOperations) {
        self.operations = operations
    }

    public func launch(
        jobId: String,
        invocation: UpdateBootstrapHandoffInvocation,
        invocationURL: URL,
        stagedBundleRoot: URL
    ) throws -> RuntimeProcessResult {
        let updater = stagedBundleRoot.appendingPathComponent(
            invocation.updaterRelativePath
        )
        try requireExecutableUpdater(updater)
        _ = try operations.submit(
            jobId,
            invocation,
            invocationURL,
            updater
        )
        try operations.startSupervisor()
        let terminal = try operations.waitForTerminal(jobId)
        return try processResult(from: terminal)
    }

    private func requireExecutableUpdater(_ updater: URL) throws {
        switch operations.fileState(updater) {
        case .executable:
            return
        case .missing:
            throw DurableUpdateBootstrapHandoffLaunchError
                .updaterUnavailable(path: updater.path)
        case .present:
            throw DurableUpdateBootstrapHandoffLaunchError
                .updaterNotExecutable(path: updater.path)
        case .inspectFailed(let reason):
            throw DurableUpdateBootstrapHandoffLaunchError
                .updaterInspectionFailed(path: updater.path, reason: reason)
        case .unknown(let state):
            throw DurableUpdateBootstrapHandoffLaunchError
                .updaterStateUnknown(path: updater.path, state: state)
        }
    }

    private func processResult(
        from job: UpdateHandoffJobDocument
    ) throws -> RuntimeProcessResult {
        guard let completion = job.completion else {
            throw DurableUpdateBootstrapHandoffLaunchError
                .terminalCompletionMissing(
                    jobId: job.jobId,
                    state: job.state
                )
        }
        let expectedOutcome: UpdateHandoffCompletionOutcome
        switch job.state {
        case .succeeded:
            expectedOutcome = .succeeded
        case .failed:
            expectedOutcome = .failed
        case .interrupted:
            expectedOutcome = .interrupted
        case .queued, .launching, .running, .cancellationRequested:
            throw DurableUpdateBootstrapHandoffLaunchError
                .terminalCompletionMissing(
                    jobId: job.jobId,
                    state: job.state
                )
        }
        guard completion.outcome == expectedOutcome else {
            throw DurableUpdateBootstrapHandoffLaunchError
                .terminalOutcomeMismatch(
                    jobId: job.jobId,
                    state: job.state,
                    outcome: completion.outcome
                )
        }
        if job.state == .succeeded, completion.exitCode != 0 {
            throw DurableUpdateBootstrapHandoffLaunchError
                .succeededWithoutZeroExitCode(
                    jobId: job.jobId,
                    exitCode: completion.exitCode
                )
        }
        return RuntimeProcessResult(
            exitCode: completion.exitCode ?? 70,
            stdout: "",
            stderr: completion.reason ?? ""
        )
    }
}
