import Contracts
import Foundation
import Errors

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
    public let containerObservation: RuntimeObservationInput<RuntimeContainerObservation>

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
        containerObservation: RuntimeObservationInput<RuntimeContainerObservation>
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
    public let restartGuestLogSync: Bool
    public let restartProxy: Bool
    public let restartReasons: [RuntimeRecoveryRestartReason]
    public let blockers: [String]

    public init(
        canRecover: Bool,
        restartVM: Bool,
        restartGuestLogSync: Bool,
        restartProxy: Bool,
        restartReasons: [RuntimeRecoveryRestartReason] = [],
        blockers: [String] = []
    ) {
        self.canRecover = canRecover
        self.restartVM = restartVM
        self.restartGuestLogSync = restartGuestLogSync
        self.restartProxy = restartProxy
        self.restartReasons = restartReasons
        self.blockers = blockers
    }

    public var restartReasonCodes: [String] {
        restartReasons.map(\.code)
    }
}

public enum RuntimeRecoveryRestartReason: Equatable, Sendable {
    case vmServiceNotLoaded(String)
    case missingVMIP
    case guestHTTPUnhealthy(String)
    case containerFailureRequiresVMRestart
    case vmRestartRequiresProxyRestart
    case proxyServiceNotLoaded(String)
    case hostProxyLivenessUnhealthy(String)
    case hostProxyReadinessUnhealthy(String)

    public var code: String {
        switch self {
        case .vmServiceNotLoaded(let state):
            "vm-service-not-loaded-\(runtimeRecoveryFailureToken(state))"
        case .missingVMIP:
            "missing-vm-ip"
        case .guestHTTPUnhealthy(let status):
            "guest-http-unhealthy-\(runtimeRecoveryFailureToken(status))"
        case .containerFailureRequiresVMRestart:
            "container-failure-requires-vm-restart"
        case .vmRestartRequiresProxyRestart:
            "vm-restart-requires-proxy-restart"
        case .proxyServiceNotLoaded(let state):
            "proxy-service-not-loaded-\(runtimeRecoveryFailureToken(state))"
        case .hostProxyLivenessUnhealthy(let status):
            "host-proxy-liveness-unhealthy-\(runtimeRecoveryFailureToken(status))"
        case .hostProxyReadinessUnhealthy(let status):
            "host-proxy-readiness-unhealthy-\(runtimeRecoveryFailureToken(status))"
        }
    }
}

public enum RuntimeRecoveryPlanner {
    public static func plan(_ input: RuntimeRecoveryInput) -> RuntimeRecoveryPlan {
        guard input.vmExecutable,
              input.proxyExecutable,
              input.rootfsBase == .present,
              input.vmDisk == .present else {
            return RuntimeRecoveryPlan(
                canRecover: false,
                restartVM: false,
                restartGuestLogSync: false,
                restartProxy: false
            )
        }

        let blockers = recoveryBlockers(input)
        guard blockers.isEmpty else {
            return RuntimeRecoveryPlan(
                canRecover: false,
                restartVM: false,
                restartGuestLogSync: false,
                restartProxy: false,
                blockers: blockers
            )
        }

        let guestHTTP = classifyHTTPStatus(input.guestHTTP, allowsPendingStatus: true)
        let hostProxyReadinessHTTP = classifyHTTPStatus(input.hostProxyReadinessHTTP)
        let hostProxyLivenessHTTP = classifyHTTPStatus(input.hostProxyLivenessHTTP)

        let waitingForGuest = input.vmLifecycle?.isWaitingForGuest(at: input.now) ?? false
        let containerFailureRequiresRestart = RuntimeObservationHealthPolicy.requiresVMRestart(
            containerObservation: input.containerObservation
        )

        let vmRestartReasons = vmRestartReasons(
            input: input,
            guestHTTP: guestHTTP,
            waitingForGuest: waitingForGuest,
            containerFailureRequiresRestart: containerFailureRequiresRestart
        )
        let proxyRestartReasons = proxyRestartReasons(
            input: input,
            guestHTTP: guestHTTP,
            hostProxyReadinessHTTP: hostProxyReadinessHTTP,
            hostProxyLivenessHTTP: hostProxyLivenessHTTP,
            vmRestartRequired: !vmRestartReasons.isEmpty
        )

        return RuntimeRecoveryPlan(
            canRecover: true,
            restartVM: !vmRestartReasons.isEmpty,
            restartGuestLogSync: !vmRestartReasons.isEmpty,
            restartProxy: !proxyRestartReasons.isEmpty,
            restartReasons: vmRestartReasons + proxyRestartReasons
        )
    }

    private enum RuntimeRecoveryHTTPStatus {
        case successful
        case unsuccessful
        case readFailed(String)

        var isSuccessful: Bool {
            if case .successful = self {
                return true
            }
            return false
        }

        var isReadFailure: Bool {
            if case .readFailed = self {
                return true
            }
            return false
        }
    }

    private static func classifyHTTPStatus(
        _ value: String,
        allowsPendingStatus: Bool = false
    ) -> RuntimeRecoveryHTTPStatus {
        let isGuestPendingStatus = value == RuntimeHTTPStatusText.bootstrapPending
            || value == RuntimeHTTPStatusText.missingVMIP
        if allowsPendingStatus && isGuestPendingStatus {
            return .unsuccessful
        }
        guard let code = Int(value) else {
            return .readFailed(value)
        }
        return code >= 200 && code < 300 ? .successful : .unsuccessful
    }

    private static func recoveryBlockers(_ input: RuntimeRecoveryInput) -> [String] {
        var blockers: [String] = []

        if input.vmService.isReadFailure {
            blockers.append("recovery-blocked-vm-service-state-\(runtimeRecoveryFailureToken(input.vmService.rawValue))")
        }
        if input.proxyService.isReadFailure {
            blockers.append("recovery-blocked-proxy-service-state-\(runtimeRecoveryFailureToken(input.proxyService.rawValue))")
        }

        let guestHTTP = classifyHTTPStatus(input.guestHTTP, allowsPendingStatus: true)
        let hostProxyReadinessHTTP = classifyHTTPStatus(input.hostProxyReadinessHTTP)
        let hostProxyLivenessHTTP = classifyHTTPStatus(input.hostProxyLivenessHTTP)

        if case .readFailed(let status) = guestHTTP {
            blockers.append("recovery-blocked-guest-http-read-failed-\(runtimeRecoveryFailureToken(status))")
        }
        if case .readFailed(let status) = hostProxyReadinessHTTP {
            blockers.append("recovery-blocked-host-proxy-readiness-http-read-failed-\(runtimeRecoveryFailureToken(status))")
        }
        if case .readFailed(let status) = hostProxyLivenessHTTP {
            blockers.append("recovery-blocked-host-proxy-liveness-http-read-failed-\(runtimeRecoveryFailureToken(status))")
        }

        let vmRestartDependsOnGuestState = input.vmService == .loaded
            && (input.vmIP == nil
                || (!guestHTTP.isReadFailure && !guestHTTP.isSuccessful)
                || RuntimeObservationHealthPolicy.requiresVMRestart(containerObservation: input.containerObservation))
        if vmRestartDependsOnGuestState, input.vmLifecycle == nil {
            blockers.append("recovery-blocked-missing-vm-lifecycle-for-vm-restart")
        }

        return blockers
    }

    private static func vmRestartReasons(
        input: RuntimeRecoveryInput,
        guestHTTP: RuntimeRecoveryHTTPStatus,
        waitingForGuest: Bool,
        containerFailureRequiresRestart: Bool
    ) -> [RuntimeRecoveryRestartReason] {
        guard !waitingForGuest else {
            return []
        }

        var reasons: [RuntimeRecoveryRestartReason] = []
        if input.vmService == .notLoaded {
            reasons.append(.vmServiceNotLoaded(input.vmService.rawValue))
        }
        if input.vmIP == nil {
            reasons.append(.missingVMIP)
        }
        if !guestHTTP.isSuccessful {
            reasons.append(.guestHTTPUnhealthy(input.guestHTTP))
        }
        if containerFailureRequiresRestart {
            reasons.append(.containerFailureRequiresVMRestart)
        }
        return reasons
    }

    private static func proxyRestartReasons(
        input: RuntimeRecoveryInput,
        guestHTTP: RuntimeRecoveryHTTPStatus,
        hostProxyReadinessHTTP: RuntimeRecoveryHTTPStatus,
        hostProxyLivenessHTTP: RuntimeRecoveryHTTPStatus,
        vmRestartRequired: Bool
    ) -> [RuntimeRecoveryRestartReason] {
        var reasons: [RuntimeRecoveryRestartReason] = []
        if vmRestartRequired {
            reasons.append(.vmRestartRequiresProxyRestart)
        }
        if input.proxyService == .notLoaded {
            reasons.append(.proxyServiceNotLoaded(input.proxyService.rawValue))
        }
        if !hostProxyLivenessHTTP.isSuccessful {
            reasons.append(.hostProxyLivenessUnhealthy(input.hostProxyLivenessHTTP))
        }
        if !hostProxyReadinessHTTP.isSuccessful, guestHTTP.isSuccessful {
            reasons.append(.hostProxyReadinessUnhealthy(input.hostProxyReadinessHTTP))
        }
        return reasons
    }
}

fileprivate func runtimeRecoveryFailureToken(_ value: String) -> String {
    value
        .trimmingCharacters(in: .whitespacesAndNewlines)
        .unicodeScalars
        .map { scalar in
            CharacterSet.alphanumerics.contains(scalar)
                || scalar == "-"
                || scalar == "_"
                || scalar == "."
                ? Character(scalar)
                : "_"
        }
        .prefix(80)
        .map(String.init)
        .joined()
}
