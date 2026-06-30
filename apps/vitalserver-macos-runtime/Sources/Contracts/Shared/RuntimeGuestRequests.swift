public struct RuntimeGuestActivationRequest: Equatable, Sendable {
    public let id: String
    public let requestedAt: String
    public let version: String

    public init(id: String, requestedAt: String, version: String) {
        self.id = id
        self.requestedAt = requestedAt
        self.version = version
    }
}

public struct RuntimeDatastoreRepairRequest: Equatable, Sendable {
    public let id: String
    public let requestedAt: String

    public init(id: String, requestedAt: String) {
        self.id = id
        self.requestedAt = requestedAt
    }
}

public struct RuntimeGuestComposeReconcileRequest: Equatable, Sendable {
    public let id: String
    public let requestedAt: String
    public let composeAction: RuntimeGuestComposeAction

    public init(
        id: String,
        requestedAt: String,
        composeAction: RuntimeGuestComposeAction = .up
    ) {
        self.id = id
        self.requestedAt = requestedAt
        self.composeAction = composeAction
    }
}

public enum RuntimeGuestComposeAction: String, Equatable, Sendable {
    case up
    case testkitUp = "testkit-up"
    case testkitStop = "testkit-stop"
    case testkitRestart = "testkit-restart"
}

public struct RuntimeGuestShutdownRequest: Equatable, Sendable {
    public let id: String
    public let requestedAt: String
    public let version: String

    public init(id: String, requestedAt: String, version: String) {
        self.id = id
        self.requestedAt = requestedAt
        self.version = version
    }
}
