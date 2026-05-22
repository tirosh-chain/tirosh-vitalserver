import Foundation

public struct RuntimeHealthInput: Equatable {
    public let vmExecutable: Bool
    public let proxyExecutable: Bool
    public let rootfsBase: String
    public let vmDisk: String
    public let vmService: String
    public let proxyService: String
    public let watchdogService: String
    public let vmIP: String?
    public let proxyPort: Int
    public let hostProxyHTTP: String
    public let guestHTTP: String
    public let redisUIHTTP: String
    public let swaggerUIHTTP: String
    public let proxyPortFailureReasons: [RuntimeFailureReason]
    public let guestBootstrapFailureReason: RuntimeFailureReason?

    public init(
        vmExecutable: Bool,
        proxyExecutable: Bool,
        rootfsBase: String,
        vmDisk: String,
        vmService: String,
        proxyService: String,
        watchdogService: String,
        vmIP: String?,
        proxyPort: Int,
        hostProxyHTTP: String,
        guestHTTP: String,
        redisUIHTTP: String,
        swaggerUIHTTP: String,
        proxyPortFailureReasons: [RuntimeFailureReason] = [],
        guestBootstrapFailureReason: RuntimeFailureReason? = nil
    ) {
        self.vmExecutable = vmExecutable
        self.proxyExecutable = proxyExecutable
        self.rootfsBase = rootfsBase
        self.vmDisk = vmDisk
        self.vmService = vmService
        self.proxyService = proxyService
        self.watchdogService = watchdogService
        self.vmIP = vmIP
        self.proxyPort = proxyPort
        self.hostProxyHTTP = hostProxyHTTP
        self.guestHTTP = guestHTTP
        self.redisUIHTTP = redisUIHTTP
        self.swaggerUIHTTP = swaggerUIHTTP
        self.proxyPortFailureReasons = proxyPortFailureReasons
        self.guestBootstrapFailureReason = guestBootstrapFailureReason
    }
}

public enum RuntimeHealthEvaluator {
    public static func evaluate(_ input: RuntimeHealthInput) -> RuntimeHealthSnapshot {
        var failureReasons: [RuntimeFailureReason] = []

        if !input.vmExecutable {
            failureReasons.append(.missingVMBin)
        }
        if !input.proxyExecutable {
            failureReasons.append(.missingProxyRunner)
        }
        if input.rootfsBase != "present" {
            failureReasons.append(.missingRootfsBase)
        }
        if input.vmDisk != "present" {
            failureReasons.append(.missingVMDisk)
        }
        if input.vmService != "loaded" {
            failureReasons.append(.vmService(input.vmService))
        }
        if input.proxyService != "loaded" {
            failureReasons.append(.proxyService(input.proxyService))
        }
        if input.watchdogService != "loaded" {
            failureReasons.append(.watchdogService(input.watchdogService))
        }
        if !isSuccessfulHTTPStatus(input.hostProxyHTTP) {
            failureReasons.append(.hostProxyHTTP(input.hostProxyHTTP))
            failureReasons.append(contentsOf: input.proxyPortFailureReasons)
        }
        if !isSuccessfulHTTPStatus(input.guestHTTP) {
            failureReasons.append(.guestHTTP(input.guestHTTP))
            if let guestBootstrapFailureReason = input.guestBootstrapFailureReason {
                failureReasons.append(guestBootstrapFailureReason)
            }
        }

        return RuntimeHealthSnapshot(
            vmExecutable: input.vmExecutable,
            proxyExecutable: input.proxyExecutable,
            rootfsBase: input.rootfsBase,
            vmDisk: input.vmDisk,
            vmService: input.vmService,
            proxyService: input.proxyService,
            watchdogService: input.watchdogService,
            vmIP: input.vmIP,
            proxyPort: input.proxyPort,
            hostProxyHTTP: input.hostProxyHTTP,
            guestHTTP: input.guestHTTP,
            redisUIHTTP: input.redisUIHTTP,
            swaggerUIHTTP: input.swaggerUIHTTP,
            failureReasons: failureReasons
        )
    }

    private static func isSuccessfulHTTPStatus(_ value: String) -> Bool {
        guard let code = Int(value) else {
            return false
        }
        return code >= 200 && code < 300
    }
}
