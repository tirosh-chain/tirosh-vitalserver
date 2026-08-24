import Foundation
import Network

public enum RuntimeGuestControlEndpointPolicy {
    public static func isLoopbackHost(_ host: String) -> Bool {
        let normalized = host.hasSuffix(".")
            ? String(host.dropLast())
            : host
        let lowered = normalized.lowercased()
        if lowered == "localhost" {
            return true
        }
        if lowered.hasSuffix(".localhost") {
            return true
        }
        if let ipv4 = IPv4Address(lowered), ipv4.rawValue.first == 127 {
            return true
        }
        if let ipv6 = IPv6Address(lowered), ipv6.isLoopback {
            return true
        }
        if isDottedNumeric(lowered),
           lowered.split(separator: ".", omittingEmptySubsequences: false)
               .first == "127" {
            return true
        }
        return false
    }

    public static func isAcceptableGuestControlBaseURL(_ rawValue: String) -> Bool {
        guard let url = URL(string: rawValue),
              url.scheme == "http",
              let host = url.host,
              !host.isEmpty,
              !isLoopbackHost(host),
              url.user == nil,
              url.password == nil,
              url.query == nil,
              url.fragment == nil,
              url.path.isEmpty || url.path == "/" else {
            return false
        }
        return true
    }

    private static func isDottedNumeric(_ value: String) -> Bool {
        let labels = value.split(
            separator: ".",
            omittingEmptySubsequences: false
        )
        guard !labels.isEmpty else {
            return false
        }
        return labels.allSatisfy { label in
            !label.isEmpty && label.allSatisfy(\.isNumber)
        }
    }
}
