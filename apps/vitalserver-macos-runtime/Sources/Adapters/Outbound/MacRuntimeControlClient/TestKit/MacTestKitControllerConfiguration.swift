import Foundation
import Contracts
import RuntimeControl
import Errors

public enum MacTestKitAPIEndpointSource: Equatable, Sendable {
    case explicit(baseURL: String)
    case runtimeStatusVMIP(port: Int)

    func baseURL(from status: RuntimeStatus) -> String? {
        switch self {
        case .explicit(let baseURL):
            let normalized = baseURL.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
            return normalized.isEmpty ? nil : normalized
        case .runtimeStatusVMIP(let port):
            guard let vmIP = status.vmIP, !vmIP.isEmpty else {
                return nil
            }
            return "http://\(vmIP):\(port)"
        }
    }

    var unavailableDescription: String {
        switch self {
        case .explicit:
            return "TestKit container API endpoint is not configured."
        case .runtimeStatusVMIP:
            return "TestKit container API is unavailable because the VM IP is not known yet."
        }
    }
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
