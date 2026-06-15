import Contracts
import Errors

struct RuntimeLaunchdCommandFailureReporter {
    let launchctlPath: String
    let log: (String) -> Void

    func requireSuccess(
        _ result: RuntimeProcessResult,
        service: RuntimeManagedService,
        action: String,
        arguments: [String]
    ) throws {
        guard result.exitCode == 0 else {
            throw failure(result, service: service, action: action, arguments: arguments)
        }
    }

    func failure(
        _ result: RuntimeProcessResult,
        service: RuntimeManagedService,
        action: String,
        arguments: [String]
    ) -> RuntimeServiceControllerError {
        logFailure(result, service: service, action: action, arguments: arguments)
        return RuntimeServiceControllerError.runtimeOperationFailed(
            "launchd command failed action=\(action) label=\(service.label) exitCode=\(result.exitCode)"
        )
    }

    func logFailure(
        _ result: RuntimeProcessResult,
        service: RuntimeManagedService,
        action: String,
        arguments: [String]
    ) {
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            log("command stderr executable=\(launchctlPath) stderr=\(stderr)")
        }
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stdout.isEmpty {
            log("command stdout executable=\(launchctlPath) stdout=\(stdout)")
        }
        if !result.outputIssues.isEmpty {
            let summary = result.outputIssues
                .map { "\($0.stream.rawValue): \($0.message)" }
                .joined(separator: "; ")
            log("command output issues executable=\(launchctlPath) issues=\(summary)")
        }
        log(
            "command failed executable=\(launchctlPath) action=\(action) label=\(service.label) "
                + "exitCode=\(result.exitCode) arguments=\(arguments.joined(separator: " "))"
        )
    }
}
