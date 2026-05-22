public struct RuntimeRecoveryInput: Equatable {
    public let vmExecutable: Bool
    public let proxyExecutable: Bool
    public let rootfsBase: String
    public let vmDisk: String
    public let vmService: String
    public let proxyService: String
    public let vmIP: String?
    public let guestHTTP: String
    public let hostProxyReadinessHTTP: String
    public let hostProxyLivenessHTTP: String

    public init(
        vmExecutable: Bool,
        proxyExecutable: Bool,
        rootfsBase: String,
        vmDisk: String,
        vmService: String,
        proxyService: String,
        vmIP: String?,
        guestHTTP: String,
        hostProxyReadinessHTTP: String,
        hostProxyLivenessHTTP: String
    ) {
        self.vmExecutable = vmExecutable
        self.proxyExecutable = proxyExecutable
        self.rootfsBase = rootfsBase
        self.vmDisk = vmDisk
        self.vmService = vmService
        self.proxyService = proxyService
        self.vmIP = vmIP
        self.guestHTTP = guestHTTP
        self.hostProxyReadinessHTTP = hostProxyReadinessHTTP
        self.hostProxyLivenessHTTP = hostProxyLivenessHTTP
    }
}

public struct RuntimeRecoveryPlan: Equatable {
    public let canRecover: Bool
    public let restartVM: Bool
    public let restartProxy: Bool

    public init(canRecover: Bool, restartVM: Bool, restartProxy: Bool) {
        self.canRecover = canRecover
        self.restartVM = restartVM
        self.restartProxy = restartProxy
    }
}

public enum RuntimeRecoveryPlanner {
    public static func plan(_ input: RuntimeRecoveryInput) -> RuntimeRecoveryPlan {
        guard input.vmExecutable,
              input.proxyExecutable,
              input.rootfsBase == "present",
              input.vmDisk == "present" else {
            return RuntimeRecoveryPlan(canRecover: false, restartVM: false, restartProxy: false)
        }

        let guestReady = isSuccessfulHTTPStatus(input.guestHTTP)
        let hostProxyReady = isSuccessfulHTTPStatus(input.hostProxyReadinessHTTP)
        let hostProxyAlive = isSuccessfulHTTPStatus(input.hostProxyLivenessHTTP)

        let restartVM = input.vmService != "loaded"
            || input.vmIP == nil
            || !guestReady

        let restartProxy = input.proxyService != "loaded"
            || !hostProxyAlive
            || (!hostProxyReady && guestReady)

        return RuntimeRecoveryPlan(
            canRecover: true,
            restartVM: restartVM,
            restartProxy: restartProxy
        )
    }

    private static func isSuccessfulHTTPStatus(_ value: String) -> Bool {
        guard let code = Int(value) else {
            return false
        }
        return code >= 200 && code < 300
    }
}
