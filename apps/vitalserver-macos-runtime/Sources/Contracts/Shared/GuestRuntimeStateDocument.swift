import Foundation

public struct GuestRuntimeStateDocument: Codable, Equatable, Sendable {
    public let capabilities: GuestRuntimeCapabilities?
    public let vmIP: String?
    public let updatedAt: String?
    public let bootID: String?
    public let guestHTTP: String?
    public let redisUIHTTP: String?
    public let swaggerUIHTTP: String?
    public let cpuUsagePercent: Double?
    public let memory: ResourceUsage?
    public let systemDisk: ResourceUsage?
    public let diskHealth: GuestDiskHealthDocument?
    public let vitalFilesDisk: ResourceUsage?
    public let containerServices: [RuntimeContainerServiceObservation]?
    public let probeErrors: [GuestRuntimeProbeError]?
    public let vitalDBObservation: VitalDBObservationDocument?

    public init(
        capabilities: GuestRuntimeCapabilities? = nil,
        vmIP: String?,
        updatedAt: String? = nil,
        bootID: String? = nil,
        guestHTTP: String?,
        redisUIHTTP: String?,
        swaggerUIHTTP: String?,
        cpuUsagePercent: Double? = nil,
        memory: ResourceUsage? = nil,
        systemDisk: ResourceUsage? = nil,
        diskHealth: GuestDiskHealthDocument? = nil,
        vitalFilesDisk: ResourceUsage? = nil,
        containerServices: [RuntimeContainerServiceObservation]? = nil,
        probeErrors: [GuestRuntimeProbeError]? = nil,
        vitalDBObservation: VitalDBObservationDocument? = nil
    ) {
        self.capabilities = capabilities
        self.vmIP = vmIP
        self.updatedAt = updatedAt
        self.bootID = bootID
        self.guestHTTP = guestHTTP
        self.redisUIHTTP = redisUIHTTP
        self.swaggerUIHTTP = swaggerUIHTTP
        self.cpuUsagePercent = cpuUsagePercent
        self.memory = memory
        self.systemDisk = systemDisk
        self.diskHealth = diskHealth
        self.vitalFilesDisk = vitalFilesDisk
        self.containerServices = containerServices
        self.probeErrors = probeErrors
        self.vitalDBObservation = vitalDBObservation
    }

}

public struct GuestDiskHealthDocument: Codable, Equatable, Sendable {
    public let rootFilesystemReadOnly: Bool?
    public let kernelErrors: [String]?

    public init(
        rootFilesystemReadOnly: Bool?,
        kernelErrors: [String]?
    ) {
        self.rootFilesystemReadOnly = rootFilesystemReadOnly
        self.kernelErrors = kernelErrors
    }
}

public struct GuestRuntimeProbeError: Codable, Equatable, Sendable {
    public let source: String
    public let message: String

    public init(source: String, message: String) {
        self.source = source
        self.message = message
    }
}

public struct GuestRuntimeCapabilities: Codable, Equatable, Sendable {
    public let prepareUpdateShutdown: Bool
    public let activateUpdate: Bool
    public let redisBackup: Bool
    public let redisRestore: Bool
    public let repairDatastore: Bool
    public let reconcileCompose: Bool

    private enum CodingKeys: String, CodingKey {
        case prepareUpdateShutdown
        case activateUpdate
        case redisBackup
        case redisRestore
        case repairDatastore
        case reconcileCompose
    }

    public init(
        prepareUpdateShutdown: Bool,
        activateUpdate: Bool,
        redisBackup: Bool,
        redisRestore: Bool,
        repairDatastore: Bool,
        reconcileCompose: Bool = false
    ) {
        self.prepareUpdateShutdown = prepareUpdateShutdown
        self.activateUpdate = activateUpdate
        self.redisBackup = redisBackup
        self.redisRestore = redisRestore
        self.repairDatastore = repairDatastore
        self.reconcileCompose = reconcileCompose
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            prepareUpdateShutdown: try container.decode(Bool.self, forKey: .prepareUpdateShutdown),
            activateUpdate: try container.decode(Bool.self, forKey: .activateUpdate),
            redisBackup: try container.decode(Bool.self, forKey: .redisBackup),
            redisRestore: try container.decode(Bool.self, forKey: .redisRestore),
            repairDatastore: try container.decode(Bool.self, forKey: .repairDatastore),
            reconcileCompose: try container.decodeIfPresent(Bool.self, forKey: .reconcileCompose) ?? false
        )
    }
}
