import Foundation
import Core
import Contracts

struct LaunchdRuntimeServiceManager: RuntimeServiceManager {
    private let commandRunner: RuntimeCommandRunner

    init(commandRunner: RuntimeCommandRunner) {
        self.commandRunner = commandRunner
    }

    func state(service: RuntimeManagedService) -> RuntimeServiceState {
        let result = commandRunner.run(
            Constants.Commands.launchctl,
            arguments: ["print", "system/\(service.label)"]
        )
        guard result.exitCode != 0 else {
            return .loaded
        }

        let message = commandFailureMessage(result)
        let lowercased = message.lowercased()
        if lowercased.contains("could not find service")
            || lowercased.contains("no such process")
            || lowercased.contains("not found")
        {
            return .notLoaded
        }
        if lowercased.contains("permission denied")
            || lowercased.contains("operation not permitted")
        {
            return .permissionDenied(message)
        }
        return .readFailed(message)
    }

    func start(service: RuntimeManagedService, plist: String) {
        let bootstrap = commandRunner.run(
            Constants.Commands.launchctl,
            arguments: ["bootstrap", "system", plist]
        )
        if bootstrap.exitCode != 0 {
            _ = commandRunner.run(
                Constants.Commands.launchctl,
                arguments: ["kickstart", "-k", "system/\(service.label)"]
            )
        }
    }

    func restart(service: RuntimeManagedService) {
        _ = commandRunner.run(
            Constants.Commands.launchctl,
            arguments: ["kickstart", "-k", "system/\(service.label)"]
        )
    }

    func stop(service: RuntimeManagedService) {
        _ = commandRunner.run(
            Constants.Commands.launchctl,
            arguments: ["bootout", "system/\(service.label)"]
        )
    }

    func setEnabled(service: RuntimeManagedService, enabled: Bool) -> RuntimeProcessResult {
        let action = enabled ? "enable" : "disable"
        return commandRunner.run(
            Constants.Commands.launchctl,
            arguments: [action, "system/\(service.label)"]
        )
    }

    private func commandFailureMessage(_ result: RuntimeProcessResult) -> String {
        let stderr = result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        let stdout = result.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
        if !stderr.isEmpty {
            return "exitCode=\(result.exitCode) stderr=\(stderr)"
        }
        if !stdout.isEmpty {
            return "exitCode=\(result.exitCode) stdout=\(stdout)"
        }
        return "exitCode=\(result.exitCode)"
    }
}
