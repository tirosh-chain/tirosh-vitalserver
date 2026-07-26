import Contracts
import Errors

public enum RuntimeReadinessPolicy {
    public static func isReady(_ status: PlatformState) -> Bool {
        status.runtimeInstallationState.isExecutable
            && serviceIsLoaded(status.serviceState(.runtimeProvider))
            && serviceIsLoaded(status.serviceState(.publicProxy))
            && serviceIsLoaded(status.serviceState(.watchdog))
            && status.platformHealth == .healthy
            && status.runtimeEndpoint != nil
            && isSuccessfulHTTPStatus(status.runtimeControllerHTTP)
            && isSuccessfulHTTPStatus(status.publicProxyHTTP)
    }

    private static func serviceIsLoaded(_ state: RuntimeServiceState?) -> Bool {
        state == .loaded
    }

    private static func isSuccessfulHTTPStatus(_ value: String?) -> Bool {
        guard let value, let code = Int(value) else {
            return false
        }
        return code >= 200 && code < 300
    }
}
