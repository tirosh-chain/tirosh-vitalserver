import RuntimeControl
import Errors

enum RuntimeLogPresentationOptions {
    static let lineLimits = [100, 500, 1000]

    static let sources: [RuntimeLogSourceOption] = [
        RuntimeLogSourceOption(id: .helperMessage, title: "Helper message"),
        RuntimeLogSourceOption(id: .install, title: "Install log"),
        RuntimeLogSourceOption(id: .command, title: "Command log"),
        RuntimeLogSourceOption(id: .launcher, title: "VM launcher"),
        RuntimeLogSourceOption(id: .vmLaunchOutput, title: "VM launch output"),
        RuntimeLogSourceOption(id: .vmLaunchError, title: "VM launch error"),
        RuntimeLogSourceOption(id: .proxyOutput, title: "Host proxy output"),
        RuntimeLogSourceOption(id: .proxyError, title: "Host proxy error"),
        RuntimeLogSourceOption(id: .watchdog, title: "Watchdog"),
        RuntimeLogSourceOption(id: .updateActivation, title: "Update activation"),
        RuntimeLogSourceOption(id: .updateShutdown, title: "Update shutdown"),
        RuntimeLogSourceOption(id: .containers, title: "Containers"),
    ]
}
