import Foundation
import Contracts
import RuntimeControl
import Errors

public enum MacTestKitAPIEndpointSource: Equatable, Sendable {
    case explicit(baseURL: String)
    case runtimeStatusVMIP(port: Int)

    func resolve(from status: RuntimeStatus) -> MacTestKitAPIEndpointResolution {
        switch self {
        case .explicit(let baseURL):
            let normalized = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return normalized.isEmpty
                ? .unavailable("TestKit container API endpoint is not configured.")
                : .available(normalized)
        case .runtimeStatusVMIP(let port):
            guard let vmIP = status.vmIP, !vmIP.isEmpty else {
                return .unavailable("TestKit container API is unavailable because the VM IP is not known yet.")
            }
            return .available("http://\(vmIP):\(port)")
        }
    }
}

public enum MacTestKitAPIEndpointResolution: Equatable, Sendable {
    case available(String)
    case unavailable(String)
}

public struct MacTestKitControllerConfiguration: Equatable, Sendable {
    public let enabled: Bool
    public let serviceName: String
    public let apiEndpoint: MacTestKitAPIEndpointSource
    public let recorderTargetURL: String

    public init(
        enabled: Bool = false,
        serviceName: String = "testkit",
        apiEndpoint: MacTestKitAPIEndpointSource = .runtimeStatusVMIP(port: 18322),
        recorderTargetURL: String = "http://edge/"
    ) {
        self.enabled = enabled
        self.serviceName = serviceName
        self.apiEndpoint = apiEndpoint
        self.recorderTargetURL = recorderTargetURL
    }
}
