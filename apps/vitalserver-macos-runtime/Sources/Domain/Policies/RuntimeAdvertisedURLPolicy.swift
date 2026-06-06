import Contracts
import Foundation
import Errors

public struct RuntimeAdvertisedEndpoint: Equatable, Sendable {
    public let publicHost: String
    public let publicPort: Int

    public init(publicHost: String, publicPort: Int) {
        self.publicHost = publicHost
        self.publicPort = publicPort
    }
}

public enum RuntimeAdvertisedURLPolicy {
    public static func isValidAdvertisedURL(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed == value,
              RuntimeTextValidator.isSingleLine(value),
              let components = URLComponents(string: value),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty else {
            return false
        }
        if let port = components.port, !(1...65_535).contains(port) {
            return false
        }
        return true
    }

    public static func compatibilityEndpoint(
        forAdvertisedURL value: String,
        defaultPublicPort: Int
    ) -> RuntimeAdvertisedEndpoint? {
        guard isValidAdvertisedURL(value),
              let components = URLComponents(string: value),
              let host = components.host else {
            return nil
        }

        if let port = components.port {
            return RuntimeAdvertisedEndpoint(publicHost: host, publicPort: port)
        }
        if components.scheme?.lowercased() == "https" {
            return RuntimeAdvertisedEndpoint(publicHost: host, publicPort: 443)
        }
        return RuntimeAdvertisedEndpoint(publicHost: host, publicPort: defaultPublicPort)
    }
}
