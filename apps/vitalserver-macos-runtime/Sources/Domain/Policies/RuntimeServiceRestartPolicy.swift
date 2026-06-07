import Contracts

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
