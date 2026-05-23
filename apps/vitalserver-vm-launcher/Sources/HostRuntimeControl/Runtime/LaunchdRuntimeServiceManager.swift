import Foundation
import RuntimeCore

struct LaunchdRuntimeServiceManager: RuntimeServiceManager {
    private let commandRunner: RuntimeCommandRunner

    init(commandRunner: RuntimeCommandRunner) {
        self.commandRunner = commandRunner
    }

    func state(service: RuntimeManagedService) -> String {
        let result = commandRunner.run(
            Constants.Commands.launchctl,
            arguments: ["print", "system/\(service.label)"]
        )
        return result.exitCode == 0 ? "loaded" : "not loaded"
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
}
