import Contracts
import Foundation
import Network

public enum UpdateBootstrapGuestControlProofPolicyError:
    Error,
    Equatable,
    Sendable
{
    case invalidURL(String)
    case hostLoopback(String)
    case guestAddressMissing(String)
    case guestAddressInvalid(String)
    case guestAddressStale(String)
    case guestAddressReadFailed(String)
    case guestAddressNotReported
    case hostMismatch(invocationHost: String, observedAddress: String)
    case portMismatch(actual: Int?, expected: Int)
}

public enum UpdateBootstrapGuestControlProofPolicy {
    public static func prove(
        persistedGuestControlBaseURL: String,
        guestAddressRead: RuntimeGuestAddressReadResult,
        expectedPort: Int
    ) throws {
        if isLoopbackURL(persistedGuestControlBaseURL) {
            throw UpdateBootstrapGuestControlProofPolicyError.hostLoopback(
                persistedGuestControlBaseURL
            )
        }
        guard RuntimeGuestControlEndpointPolicy
            .isAcceptableGuestControlBaseURL(persistedGuestControlBaseURL),
            let url = URL(string: persistedGuestControlBaseURL),
            let invocationHost = url.host,
            !invocationHost.isEmpty
        else {
            throw UpdateBootstrapGuestControlProofPolicyError.invalidURL(
                persistedGuestControlBaseURL
            )
        }

        switch guestAddressRead.state {
        case .notReported:
            throw UpdateBootstrapGuestControlProofPolicyError
                .guestAddressNotReported
        case .missing:
            throw UpdateBootstrapGuestControlProofPolicyError
                .guestAddressMissing(guestAddressRead.reason ?? "")
        case .invalid:
            throw UpdateBootstrapGuestControlProofPolicyError
                .guestAddressInvalid(guestAddressRead.reason ?? "")
        case .stale:
            throw UpdateBootstrapGuestControlProofPolicyError
                .guestAddressStale(guestAddressRead.reason ?? "")
        case .readFailed:
            throw UpdateBootstrapGuestControlProofPolicyError
                .guestAddressReadFailed(guestAddressRead.reason ?? "")
        case .loaded:
            guard let observedAddress = guestAddressRead.address,
                  !observedAddress.isEmpty
            else {
                throw UpdateBootstrapGuestControlProofPolicyError
                    .guestAddressReadFailed(
                        "loaded Guest address resource has no address"
                    )
            }
            guard hostsMatch(invocationHost, observedAddress) else {
                throw UpdateBootstrapGuestControlProofPolicyError.hostMismatch(
                    invocationHost: invocationHost,
                    observedAddress: observedAddress
                )
            }
            guard url.port == expectedPort else {
                throw UpdateBootstrapGuestControlProofPolicyError.portMismatch(
                    actual: url.port,
                    expected: expectedPort
                )
            }
        }
    }

    private static func isLoopbackURL(_ rawValue: String) -> Bool {
        guard let url = URL(string: rawValue),
              let host = url.host,
              !host.isEmpty
        else {
            return false
        }
        return RuntimeGuestControlEndpointPolicy.isLoopbackHost(host)
    }

    private static func hostsMatch(_ invocationHost: String, _ observedAddress: String) -> Bool {
        let left = stripTrailingDot(invocationHost)
        let right = stripTrailingDot(observedAddress)
        if let leftAddress = IPv4Address(left),
           let rightAddress = IPv4Address(right)
        {
            return leftAddress == rightAddress
        }
        return left == right
    }

    private static func stripTrailingDot(_ host: String) -> String {
        host.hasSuffix(".") ? String(host.dropLast()) : host
    }
}
