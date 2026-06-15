import Foundation
import Application
import Contracts
import Errors

public struct LaunchdRuntimeServiceManager: RuntimeServiceManager {
    private let commandRunner: RuntimeCommandRunner

    public init(commandRunner: RuntimeCommandRunner) {
        self.commandRunner = commandRunner
    }

    public func state(service: RuntimeManagedService) -> RuntimeServiceState {
        let result = commandRunner.run(
            "/bin/launchctl",
            arguments: ["print", "system/\(service.label)"]
        )
        return RuntimeLaunchdServiceStateMapper.state(
            exitCode: result.exitCode,
            stdout: result.stdout,
            stderr: result.stderr,
            outputIssues: result.outputIssues
        )
    }

    public func start(service: RuntimeManagedService, plist: String) -> RuntimeProcessResult {
        let bootstrap = commandRunner.run(
            "/bin/launchctl",
            arguments: ["bootstrap", "system", plist]
        )
        if bootstrap.exitCode != 0 {
            return commandRunner.run(
                "/bin/launchctl",
                arguments: ["kickstart", "-k", "system/\(service.label)"]
            )
        }
        return bootstrap
    }

    public func restart(service: RuntimeManagedService) -> RuntimeProcessResult {
        commandRunner.run(
            "/bin/launchctl",
            arguments: ["kickstart", "-k", "system/\(service.label)"]
        )
    }

    public func stop(service: RuntimeManagedService) -> RuntimeProcessResult {
        commandRunner.run(
            "/bin/launchctl",
            arguments: ["bootout", "system/\(service.label)"]
        )
    }

    public func setEnabled(service: RuntimeManagedService, enabled: Bool) -> RuntimeProcessResult {
        let action = enabled ? "enable" : "disable"
        return commandRunner.run(
            "/bin/launchctl",
            arguments: [action, "system/\(service.label)"]
        )
    }

}
