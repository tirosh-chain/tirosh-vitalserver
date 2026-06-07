import Contracts
import Foundation

public struct RuntimeUninstallReadinessInput: Equatable, Sendable {
    public let serviceStates: [RuntimeManagedService: RuntimeServiceState]
    public let vmProcessState: RuntimeVMProcessState
    public let packageReceiptStates: [RuntimePackageReceiptState]

    public init(
        serviceStates: [RuntimeManagedService: RuntimeServiceState],
        vmProcessState: RuntimeVMProcessState,
        packageReceiptStates: [RuntimePackageReceiptState] = []
    ) {
        self.serviceStates = serviceStates
        self.vmProcessState = vmProcessState
        self.packageReceiptStates = packageReceiptStates
    }
}

public enum RuntimeUninstallReadinessPolicy {
    public static func blockers(input: RuntimeUninstallReadinessInput) -> [String] {
        var blockers: [String] = []

        for service in RuntimeManagedService.stopOrder {
            guard let state = input.serviceStates[service] else {
                blockers.append("launchd-service-state-missing:label=\(service.label)")
                continue
            }
            switch state {
            case .loaded:
                blockers.append("launchd-service-loaded:label=\(service.label)")
            case .readFailed(let reason):
                blockers.append("launchd-service-read-failed:label=\(service.label) reason=\(reason)")
            case .permissionDenied(let reason):
                blockers.append("launchd-service-permission-denied:label=\(service.label) reason=\(reason)")
            case .unknown(let value):
                blockers.append("launchd-service-state-unknown:label=\(service.label) value=\(value)")
            case .notLoaded:
                continue
            }
        }

        switch input.vmProcessState {
        case .pidFileMissing:
            if input.serviceStates[.vm] != .notLoaded {
                blockers.append("vm-process-pid-file-missing")
            }
        case .running(let pid):
            blockers.append("vm-process-running:pid=\(pid)")
        case .pidFileInvalid(let reason):
            blockers.append("vm-process-pid-file-invalid:reason=\(reason)")
        case .signalFailed(let pid, let signal, let errnoCode):
            blockers.append("vm-process-signal-failed:pid=\(pid) signal=\(signal) errno=\(errnoCode)")
        case .stopTimedOut(let pid, let timeoutSeconds):
            blockers.append("vm-process-stop-timed-out:pid=\(pid) timeout-seconds=\(timeoutSeconds)")
        case .readFailed(let reason):
            blockers.append("vm-process-read-failed:reason=\(reason)")
        case .unknown(let value):
            blockers.append("vm-process-state-unknown:value=\(value)")
        case .stopped, .stalePid:
            break
        }

        blockers.append(contentsOf: packageReceiptBlockers(input.packageReceiptStates))

        return blockers
    }

    public static func cleanupArtifactBlockers(_ states: [RuntimeInstallArtifactState]) -> [String] {
        var blockers: [String] = []
        for state in states {
            switch state {
            case .present(let path):
                blockers.append("runtime-artifact-present:path=\(path)")
            case .inspectFailed(let path, let reason):
                blockers.append("runtime-artifact-inspect-failed:path=\(path) reason=\(reason)")
            case .unknown(let value):
                blockers.append("runtime-artifact-state-unknown:value=\(value)")
            case .absent:
                continue
            }
        }
        return blockers
    }

    public static func packageReceiptBlockers(_ states: [RuntimePackageReceiptState]) -> [String] {
        var blockers: [String] = []
        for state in states {
            switch state {
            case .present(let identifier):
                blockers.append("package-receipt-present:identifier=\(identifier)")
            case .readFailed(let identifier, let reason):
                blockers.append("package-receipt-read-failed:identifier=\(identifier) reason=\(reason)")
            case .forgetFailed(let identifier, let reason):
                blockers.append("package-receipt-forget-failed:identifier=\(identifier) \(reason)")
            case .unknown(let value):
                blockers.append("package-receipt-state-unknown:value=\(value)")
            case .absent:
                continue
            }
        }
        return blockers
    }
}
