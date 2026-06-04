import Contracts
import Core

public struct RuntimeHealthWaitPorts {
    public var serviceStates: ([RuntimeManagedService]) -> [RuntimeManagedService: RuntimeServiceState]
    public var healthSnapshot: () -> RuntimeHealthSnapshot

    public init(
        serviceStates: @escaping ([RuntimeManagedService]) -> [RuntimeManagedService: RuntimeServiceState],
        healthSnapshot: @escaping () -> RuntimeHealthSnapshot
    ) {
        self.serviceStates = serviceStates
        self.healthSnapshot = healthSnapshot
    }
}

public struct WaitForRuntimeHealthUseCase {
    private let ports: RuntimeHealthWaitPorts

    public init(ports: RuntimeHealthWaitPorts) {
        self.ports = ports
    }

    public func observe(policy: RuntimeServiceRestartPolicy) -> RuntimeHealthWaitObservation {
        let states = ports.serviceStates(Self.observedServices)
        return RuntimeHealthWaitObservation(
            vmServiceRequired: policy.restartVM,
            guestLogSyncServiceRequired: policy.restartGuestLogSync,
            proxyServiceRequired: policy.restartProxy,
            watchdogServiceRequired: policy.restartWatchdog,
            vmServiceLoaded: states[.vm]?.isLoaded == true,
            guestLogSyncServiceLoaded: states[.guestLogSync]?.isLoaded == true,
            proxyServiceLoaded: states[.proxy]?.isLoaded == true,
            watchdogServiceLoaded: states[.watchdog]?.isLoaded == true,
            snapshot: ports.healthSnapshot()
        )
    }

    public func currentSnapshot() -> RuntimeHealthSnapshot {
        ports.healthSnapshot()
    }

    private static let observedServices: [RuntimeManagedService] = [
        .vm,
        .guestLogSync,
        .proxy,
        .watchdog,
    ]
}
