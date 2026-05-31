import Contracts
import Foundation

public struct RuntimeRecoveryInput: Equatable {
    public let vmExecutable: Bool
    public let proxyExecutable: Bool
    public let rootfsBase: RuntimeFileState
    public let vmDisk: RuntimeFileState
    public let vmService: RuntimeServiceState
    public let proxyService: RuntimeServiceState
    public let vmLifecycle: RuntimeVMLifecycleDocument?
    public let now: Date
    public let vmIP: String?
    public let guestHTTP: String
    public let hostProxyReadinessHTTP: String
    public let hostProxyLivenessHTTP: String
    public let containerObservation: RuntimeContainerObservation?

    public init(
        vmExecutable: Bool,
        proxyExecutable: Bool,
        rootfsBase: RuntimeFileState,
        vmDisk: RuntimeFileState,
        vmService: RuntimeServiceState,
        proxyService: RuntimeServiceState,
        vmLifecycle: RuntimeVMLifecycleDocument? = nil,
        now: Date = Date(),
        vmIP: String?,
        guestHTTP: String,
        hostProxyReadinessHTTP: String,
        hostProxyLivenessHTTP: String,
        containerObservation: RuntimeContainerObservation? = nil
    ) {
        self.vmExecutable = vmExecutable
        self.proxyExecutable = proxyExecutable
        self.rootfsBase = rootfsBase
        self.vmDisk = vmDisk
        self.vmService = vmService
        self.proxyService = proxyService
        self.vmLifecycle = vmLifecycle
        self.now = now
        self.vmIP = vmIP
        self.guestHTTP = guestHTTP
        self.hostProxyReadinessHTTP = hostProxyReadinessHTTP
        self.hostProxyLivenessHTTP = hostProxyLivenessHTTP
        self.containerObservation = containerObservation
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
              input.rootfsBase == .present,
              input.vmDisk == .present else {
            return RuntimeRecoveryPlan(canRecover: false, restartVM: false, restartProxy: false)
        }

        let guestReady = isSuccessfulHTTPStatus(input.guestHTTP)
        let hostProxyReady = isSuccessfulHTTPStatus(input.hostProxyReadinessHTTP)
        let hostProxyAlive = isSuccessfulHTTPStatus(input.hostProxyLivenessHTTP)

        let waitingForGuest = input.vmLifecycle?.isWaitingForGuest(at: input.now) ?? false

        let restartVM = !waitingForGuest && (input.vmService != .loaded
            || input.vmIP == nil
            || !guestReady
            || RuntimeObservationHealthPolicy.requiresVMRestart(containerObservation: input.containerObservation))

        let restartProxy = restartVM
            || input.proxyService != .loaded
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
