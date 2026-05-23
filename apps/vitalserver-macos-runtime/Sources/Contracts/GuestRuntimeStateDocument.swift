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

    public init(
        vmIP: String?,
        updatedAt: String? = nil,
        bootID: String? = nil,
        guestHTTP: String?,
        redisUIHTTP: String?,
        swaggerUIHTTP: String?,
        cpuUsagePercent: Double? = nil,
        memory: ResourceUsage? = nil,
        systemDisk: ResourceUsage? = nil
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
    }

}
