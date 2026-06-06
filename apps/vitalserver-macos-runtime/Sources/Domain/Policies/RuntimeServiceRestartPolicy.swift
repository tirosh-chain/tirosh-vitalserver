import Contracts
import Errors

public struct RuntimeServiceRestartPolicy: Equatable, Sendable {
    public let restartVM: Bool
    public let restartGuestLogSync: Bool
    public let restartProxy: Bool
    public let restartWatchdog: Bool

    public init(
        restartVM: Bool,
        restartGuestLogSync: Bool,
        restartProxy: Bool,
        restartWatchdog: Bool
    ) {
        self.restartVM = restartVM
        self.restartGuestLogSync = restartGuestLogSync
        self.restartProxy = restartProxy
        self.restartWatchdog = restartWatchdog
    }

    public var anyServiceWasRunning: Bool {
        restartVM || restartGuestLogSync || restartProxy || restartWatchdog
    }
}

public enum RuntimeRequiredServicePolicy {
    public static let allRuntimeServices = RuntimeServiceRestartPolicy(
        restartVM: true,
        restartGuestLogSync: true,
        restartProxy: true,
        restartWatchdog: true
    )

    public static func requiredServices(
        for policy: RuntimeServiceRestartPolicy
    ) -> [RuntimeManagedService] {
        var services: [RuntimeManagedService] = []
        if policy.restartVM {
            services.append(.vm)
        }
        if policy.restartGuestLogSync {
            services.append(.guestLogSync)
        }
        if policy.restartProxy {
            services.append(.proxy)
        }
        if policy.restartWatchdog {
            services.append(.watchdog)
        }
        return services
    }
}
