public struct ServiceStackStatusDocument: Codable, Equatable, Sendable {
    public let schemaVersion: Int
    public let owner: String
    public let updatedAt: String?
    public let bootID: String?
    public let capabilities: GuestRuntimeCapabilities?
    public let composeServices: [RuntimeContainerServiceObservation]?
    public let httpProbes: ServiceStackHTTPProbesDocument?
    public let vitalDBObservation: VitalDBObservationDocument?
    public let readIssues: [GuestRuntimeProbeError]?

    public init(
        schemaVersion: Int,
        owner: String = "service-stack",
        updatedAt: String?,
        bootID: String? = nil,
        capabilities: GuestRuntimeCapabilities? = nil,
        composeServices: [RuntimeContainerServiceObservation]? = nil,
        httpProbes: ServiceStackHTTPProbesDocument? = nil,
        vitalDBObservation: VitalDBObservationDocument? = nil,
        readIssues: [GuestRuntimeProbeError]? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.owner = owner
        self.updatedAt = updatedAt
        self.bootID = bootID
        self.capabilities = capabilities
        self.composeServices = composeServices
        self.httpProbes = httpProbes
        self.vitalDBObservation = vitalDBObservation
        self.readIssues = readIssues
    }
}

public struct ServiceStackHTTPProbesDocument: Codable, Equatable, Sendable {
    public let edge: ServiceStackHTTPProbeDocument?
    public let redisUI: ServiceStackHTTPProbeDocument?
    public let swaggerUI: ServiceStackHTTPProbeDocument?

    public init(
        edge: ServiceStackHTTPProbeDocument? = nil,
        redisUI: ServiceStackHTTPProbeDocument? = nil,
        swaggerUI: ServiceStackHTTPProbeDocument? = nil
    ) {
        self.edge = edge
        self.redisUI = redisUI
        self.swaggerUI = swaggerUI
    }
}

public struct ServiceStackHTTPProbeDocument: Codable, Equatable, Sendable {
    public let status: String?
    public let failed: Bool
    public let message: String
    public let exitCode: Int?

    public init(
        status: String?,
        failed: Bool = false,
        message: String = "",
        exitCode: Int? = nil
    ) {
        self.status = status
        self.failed = failed
        self.message = message
        self.exitCode = exitCode
    }
}
