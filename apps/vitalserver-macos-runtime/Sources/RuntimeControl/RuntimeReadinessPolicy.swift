public enum RuntimeReadinessPolicy {
    public static func isReady(_ status: RuntimeStatus) -> Bool {
        status.runtimeInstalled
            && status.vmServiceLoaded
            && status.proxyServiceLoaded
            && status.watchdogServiceLoaded
            && status.runtimeState == .healthy
            && status.vmIP != nil
            && isSuccessfulHTTPStatus(status.guestHTTP)
            && isSuccessfulHTTPStatus(status.hostProxyHTTP)
    }

    private static func isSuccessfulHTTPStatus(_ value: String?) -> Bool {
        guard let value, let code = Int(value) else {
            return false
        }
        return code >= 200 && code < 300
    }
}
