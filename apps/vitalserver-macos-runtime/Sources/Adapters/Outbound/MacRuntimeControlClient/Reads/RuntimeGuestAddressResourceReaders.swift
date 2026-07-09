import Application
import Contracts
import Foundation
import RuntimeControl

public enum RuntimeGuestAddressResourceReadMapper {
    public static func readResult(
        from resource: RuntimeGuestAddressResourceState
    ) -> RuntimeGuestAddressReadResult {
        switch resource.state {
        case .loaded:
            guard let read = resource.read else {
                return .readFailed("Guest address resource loaded without read result")
            }
            guard read.state == .loaded else {
                return .readFailed("Guest address resource loaded with non-loaded read state=\(read.state.rawValue)")
            }
            return read
        case .missing:
            return .missing(resource.readError ?? "Guest address resource missing")
        case .unavailable:
            return .readFailed(resource.readError ?? "Guest address resource unavailable")
        case .failed:
            return .readFailed(resource.readError ?? "Guest address resource read failed")
        }
    }
}

public struct RuntimeControlAPIGuestAddressProvider: RuntimeGuestAddressProvider {
    private let ownerFactory: @Sendable () throws -> RuntimeControlAPIGuestAddressOwner

    public init(
        ownerFactory: @escaping @Sendable () throws -> RuntimeControlAPIGuestAddressOwner = {
            try RuntimeControlAPIGuestAddressOwner()
        }
    ) {
        self.ownerFactory = ownerFactory
    }

    public func readGuestAddress() -> RuntimeGuestAddressReadResult {
        do {
            return RuntimeGuestAddressResourceReadMapper.readResult(
                from: try ownerFactory().loadGuestAddressResource()
            )
        } catch {
            return .readFailed(String(describing: error))
        }
    }
}

public struct UnavailableRuntimeGuestAddressProvider: RuntimeGuestAddressProvider {
    private let reason: String

    public init(reason: String) {
        self.reason = reason
    }

    public func readGuestAddress() -> RuntimeGuestAddressReadResult {
        .readFailed(reason)
    }
}
