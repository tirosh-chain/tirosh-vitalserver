import Foundation

public struct GuestRuntimeStateDocument: Codable, Equatable, Sendable {
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
    public let probeErrors: [GuestRuntimeProbeError]?

    public init(
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
        probeErrors: [GuestRuntimeProbeError]? = nil
    ) {
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
        self.probeErrors = probeErrors
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
