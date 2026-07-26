import Foundation

public struct ProviderIssue: Codable, Equatable, Sendable {
    public let code: String
    public let message: String?
    public let retryable: Bool?
    public let dependency: String?

    public init(code: String, message: String? = nil, retryable: Bool? = nil, dependency: String? = nil) {
        self.code = code
        self.message = message
        self.retryable = retryable
        self.dependency = dependency
    }
}

public struct ProviderLifecycleRequest: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let requestId: String
    public let providerId: String
    public let action: String

    public init(schemaVersion: String, requestId: String, providerId: String, action: String) {
        self.schemaVersion = schemaVersion
        self.requestId = requestId
        self.providerId = providerId
        self.action = action
    }
}

// PlatformProviderLifecycleInvocation is C21. The Host Agent owns durable
// request-id/revision idempotency; the macOS adapter only verifies that it was
// given one coherent invocation before it performs an Apple Virtualization
// effect.
public struct PlatformProviderLifecycleInvocation: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let providerKind: String
    public let requestId: String
    public let expectedGuestRuntimeControlEndpointRevision: Int
    public let lifecycle: ProviderLifecycleRequest

    public init(schemaVersion: String, providerKind: String, requestId: String, expectedGuestRuntimeControlEndpointRevision: Int, lifecycle: ProviderLifecycleRequest) {
        self.schemaVersion = schemaVersion
        self.providerKind = providerKind
        self.requestId = requestId
        self.expectedGuestRuntimeControlEndpointRevision = expectedGuestRuntimeControlEndpointRevision
        self.lifecycle = lifecycle
    }

    public var isValidForMacOSVirtualization: Bool {
        schemaVersion == "v1" &&
            providerKind == "macos-virtualization" &&
            !requestId.isEmpty &&
            expectedGuestRuntimeControlEndpointRevision >= 1 &&
            lifecycle.schemaVersion == "v1" &&
            lifecycle.requestId == requestId &&
            !lifecycle.providerId.isEmpty &&
            ["start", "stop", "reboot"].contains(lifecycle.action)
    }
}

public struct ProviderLifecycleResult: Codable, Equatable, Sendable {
    public let schemaVersion: String
    public let requestId: String
    public let providerId: String
    public let observedState: String
    public let observedAt: String
    public let issue: ProviderIssue?

    public init(schemaVersion: String = "v1", requestId: String, providerId: String, observedState: String, observedAt: String, issue: ProviderIssue? = nil) {
        self.schemaVersion = schemaVersion
        self.requestId = requestId
        self.providerId = providerId
        self.observedState = observedState
        self.observedAt = observedAt
        self.issue = issue
    }
}

public enum VirtualMachineObservedState: Sendable {
    case starting
    case running
    case stopping
    case stopped
    case failed

    var contractValue: String {
        switch self {
        case .starting: "starting"
        case .running: "running"
        case .stopping: "stopping"
        case .stopped: "stopped"
        case .failed: "failed"
        }
    }
}
