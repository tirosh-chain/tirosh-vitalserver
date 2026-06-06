import Foundation

public struct ConfigureRuntimePorts<NetworkMode: Equatable> {
    public var applyConfiguration: (ConfigureRuntimeRequest<NetworkMode>) throws -> ConfigureRuntimeResult

    public init(
        applyConfiguration: @escaping (ConfigureRuntimeRequest<NetworkMode>) throws -> ConfigureRuntimeResult
    ) {
        self.applyConfiguration = applyConfiguration
    }
}

public struct ConfigureRuntimeRequest<NetworkMode: Equatable>: Equatable {
    public let changes: [ConfigureRuntimeChange<NetworkMode>]
    public let restart: Bool

    public init(
        changes: [ConfigureRuntimeChange<NetworkMode>] = [],
        restart: Bool = false
    ) {
        self.changes = changes
        self.restart = restart
    }
}

public enum ConfigureRuntimeChange<NetworkMode: Equatable>: Equatable {
    case cpu(Int)
    case memoryGiB(UInt64)
    case diskGiB(Int)
    case network(NetworkMode)
    case bridgedInterface(String)
    case proxyPort(Int)
    case vitalFilesDirectory(URL)
    case vitalServerURL(String)
    case remoteConsoleURL(String)
    case publicHost(String)
    case publicPort(Int)
    case adminPassword(String)
    case adminPasswordFile(URL)
    case startOnBoot(Bool)
    case autoRecovery(Bool)
    case preventSystemSleep(Bool)
    case redisBackupRetention(Int)
}

public struct ConfigureRuntimeResult: Equatable, Sendable {
    public let restart: Bool

    public init(restart: Bool) {
        self.restart = restart
    }
}

public struct ConfigureRuntimeUseCase<NetworkMode: Equatable> {
    private let ports: ConfigureRuntimePorts<NetworkMode>

    public init(ports: ConfigureRuntimePorts<NetworkMode>) {
        self.ports = ports
    }

    public func configure(
        _ request: ConfigureRuntimeRequest<NetworkMode>
    ) throws -> ConfigureRuntimeResult {
        try ports.applyConfiguration(request)
    }
}
