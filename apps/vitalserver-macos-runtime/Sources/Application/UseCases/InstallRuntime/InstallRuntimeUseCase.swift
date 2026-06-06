import Contracts

public struct InstallRuntimeRequest: Equatable, Sendable {
    public let mode: RuntimeInstallMode

    public init(
        mode: RuntimeInstallMode
    ) {
        self.mode = mode
    }
}

public struct InstallRuntimePorts {
    public var runInstall: (InstallRuntimeRequest) throws -> Void

    public init(
        runInstall: @escaping (InstallRuntimeRequest) throws -> Void
    ) {
        self.runInstall = runInstall
    }
}

public struct InstallRuntimeUseCase {
    private let ports: InstallRuntimePorts

    public init(ports: InstallRuntimePorts) {
        self.ports = ports
    }

    public func install(_ request: InstallRuntimeRequest) throws {
        try ports.runInstall(request)
    }
}
