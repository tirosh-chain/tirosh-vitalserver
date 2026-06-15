import Contracts
import Foundation
import Errors

public struct RuntimeServiceStopWaiter {
    private let serviceState: (RuntimeManagedService) -> RuntimeServiceState
    private let now: () -> Date
    private let sleep: (TimeInterval) -> Void
    private let waitForVMProcessStoppedAfterServiceUnload: () throws -> Void
    private let vmStopTimeoutSeconds: TimeInterval
    private let serviceStopTimeoutSeconds: TimeInterval
    private let pollIntervalSeconds: TimeInterval

    public init(
        serviceState: @escaping (RuntimeManagedService) -> RuntimeServiceState,
        now: @escaping () -> Date,
        sleep: @escaping (TimeInterval) -> Void = { Thread.sleep(forTimeInterval: $0) },
        waitForVMProcessStoppedAfterServiceUnload: @escaping () throws -> Void,
        vmStopTimeoutSeconds: TimeInterval,
        serviceStopTimeoutSeconds: TimeInterval,
        pollIntervalSeconds: TimeInterval
    ) {
        self.serviceState = serviceState
        self.now = now
        self.sleep = sleep
        self.waitForVMProcessStoppedAfterServiceUnload = waitForVMProcessStoppedAfterServiceUnload
        self.vmStopTimeoutSeconds = vmStopTimeoutSeconds
        self.serviceStopTimeoutSeconds = serviceStopTimeoutSeconds
        self.pollIntervalSeconds = pollIntervalSeconds
    }

    public func waitUntilStopped(_ service: RuntimeManagedService) throws {
        let timeout = service == .vm ? vmStopTimeoutSeconds : serviceStopTimeoutSeconds
        let deadline = now().addingTimeInterval(timeout)
        while try serviceIsLoaded(service) {
            guard now() < deadline else {
                throw RuntimeServiceControllerError.runtimeOperationFailed(
                    "service did not unload within \(Int(timeout))s label=\(service.label)"
                )
            }
            sleep(pollIntervalSeconds)
        }

        if service == .vm {
            try waitForVMProcessStoppedAfterServiceUnload()
        }
    }

    private func serviceIsLoaded(_ service: RuntimeManagedService) throws -> Bool {
        switch serviceState(service) {
        case .loaded:
            return true
        case .notLoaded:
            return false
        case .readFailed(let reason):
            throw RuntimeServiceControllerError.runtimeOperationFailed(
                "launchd service state read failed label=\(service.label) reason=\(reason)"
            )
        case .permissionDenied(let reason):
            throw RuntimeServiceControllerError.runtimeOperationFailed(
                "launchd service state permission denied label=\(service.label) reason=\(reason)"
            )
        case .unknown(let value):
            throw RuntimeServiceControllerError.runtimeOperationFailed(
                "launchd service state unknown label=\(service.label) value=\(value)"
            )
        }
    }
}
