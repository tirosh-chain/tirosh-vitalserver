import Contracts

public enum RuntimeServiceLifecycleCompletionPolicy {
    public static func requiredServicesLoaded(
        _ services: [RuntimeManagedService],
        states: [RuntimeManagedService: RuntimeServiceState]
    ) -> [String] {
        services.compactMap { service in
            guard let state = states[service] else {
                return "launchd-service-state-missing:label=\(service.label)"
            }
            guard state == .loaded else {
                return serviceStateBlocker(
                    prefix: "launchd-service-not-loaded",
                    service: service,
                    state: state
                )
            }
            return nil
        }
    }

    public static func servicesStopped(
        _ services: [RuntimeManagedService],
        states: [RuntimeManagedService: RuntimeServiceState]
    ) -> [String] {
        services.compactMap { service in
            guard let state = states[service] else {
                return "launchd-service-state-missing:label=\(service.label)"
            }
            guard state == .notLoaded else {
                return serviceStateBlocker(
                    prefix: "launchd-service-not-stopped",
                    service: service,
                    state: state
                )
            }
            return nil
        }
    }

    private static func serviceStateBlocker(
        prefix: String,
        service: RuntimeManagedService,
        state: RuntimeServiceState
    ) -> String {
        "\(prefix):label=\(service.label) state=\(state.rawValue)"
    }
}
