import Contracts
import Errors

enum RuntimeExecutableRequirement: Sendable {
    case launcher
    case uninstaller

    var path: String {
        switch self {
        case .launcher:
            return RuntimeControlClientConstants.Paths.launcher
        case .uninstaller:
            return RuntimeControlClientConstants.Paths.uninstaller
        }
    }

    var missingError: RuntimeClientError {
        switch self {
        case .launcher:
            return .missingLauncher
        case .uninstaller:
            return .missingUninstaller
        }
    }

    func inspectionFailed(path: String, reason: String) -> RuntimeClientError {
        switch self {
        case .launcher:
            return RuntimeClientError.launcherInspectionFailed(path: path, reason: reason)
        case .uninstaller:
            return RuntimeClientError.uninstallerInspectionFailed(path: path, reason: reason)
        }
    }

    func notExecutable(path: String, state: String) -> RuntimeClientError {
        switch self {
        case .launcher:
            return RuntimeClientError.launcherNotExecutable(path: path, state: state)
        case .uninstaller:
            return RuntimeClientError.uninstallerNotExecutable(path: path, state: state)
        }
    }
}

enum RuntimeExecutableCommandPreflight {
    static func requireExecutable(
        state: RuntimeFileState,
        requirement: RuntimeExecutableRequirement
    ) throws {
        switch state {
        case .executable:
            return
        case .missing:
            throw requirement.missingError
        case .inspectFailed(let reason):
            throw requirement.inspectionFailed(path: requirement.path, reason: reason)
        case .present:
            throw requirement.notExecutable(path: requirement.path, state: "present")
        case .unknown(let state):
            throw requirement.notExecutable(path: requirement.path, state: state)
        }
    }
}
