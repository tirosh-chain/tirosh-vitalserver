import Contracts
import Foundation

public enum UpdateBootstrapHandoffProcessLaunchError: Error, Equatable {
    case updaterUnavailable(path: String)
    case updaterNotExecutable(path: String)
    case updaterInspectionFailed(path: String, reason: String)
    case updaterStateUnknown(path: String, state: String)
    case processLaunchFailed(path: String, reason: String)
}

public struct UpdateBootstrapHandoffProcessLaunchOperations {
    public let fileState: (URL) -> RuntimeFileState
    public let run: (String, [String]) -> RuntimeProcessResult

    public init(
        fileState: @escaping (URL) -> RuntimeFileState,
        run: @escaping (String, [String]) -> RuntimeProcessResult
    ) {
        self.fileState = fileState
        self.run = run
    }
}

public struct UpdateBootstrapHandoffProcessLauncher {
    public let operations: UpdateBootstrapHandoffProcessLaunchOperations

    public init(operations: UpdateBootstrapHandoffProcessLaunchOperations) {
        self.operations = operations
    }

    public func launch(
        invocation: UpdateBootstrapHandoffInvocation,
        invocationURL: URL,
        stagedBundleRoot: URL
    ) throws -> RuntimeProcessResult {
        let updater = stagedBundleRoot.appendingPathComponent(
            invocation.updaterRelativePath
        )
        switch operations.fileState(updater) {
        case .executable:
            break
        case .missing:
            throw UpdateBootstrapHandoffProcessLaunchError.updaterUnavailable(
                path: updater.path
            )
        case .present:
            throw UpdateBootstrapHandoffProcessLaunchError.updaterNotExecutable(
                path: updater.path
            )
        case .inspectFailed(let reason):
            throw UpdateBootstrapHandoffProcessLaunchError
                .updaterInspectionFailed(path: updater.path, reason: reason)
        case .unknown(let value):
            throw UpdateBootstrapHandoffProcessLaunchError
                .updaterStateUnknown(path: updater.path, state: value)
        }

        let result = operations.run(
            updater.path,
            ["execute", "--invocation", invocationURL.path]
        )
        if let issue = result.executionIssue {
            throw UpdateBootstrapHandoffProcessLaunchError.processLaunchFailed(
                path: updater.path,
                reason: issue.message
            )
        }
        return result
    }
}
