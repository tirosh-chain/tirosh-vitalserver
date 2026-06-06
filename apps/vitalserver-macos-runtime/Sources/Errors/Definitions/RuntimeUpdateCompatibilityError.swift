import Foundation
import Contracts

public enum RuntimeUpdateCompatibilityError: Error, Equatable, CustomStringConvertible {
    case updaterTooOld(currentVersion: String, minimumVersion: String)
    case unsupportedChannel(currentChannel: UpdateBundleChannel, bundleChannel: UpdateBundleChannel)
    case twoPhaseUpdateRequired
    case unsupportedPlatform(currentPlatform: String, targetPlatform: String)
    case guestActivationRequirementMismatch(requiresGuestActivation: Bool, hasGuestDeployArtifact: Bool)

    public var description: String {
        switch self {
        case let .updaterTooOld(currentVersion, minimumVersion):
            return "update bundle requires updater \(minimumVersion) or newer; current updater is \(currentVersion)"
        case let .unsupportedChannel(currentChannel, bundleChannel):
            return "update bundle channel \(bundleChannel.rawValue) is not compatible with installed channel \(currentChannel.rawValue)"
        case .twoPhaseUpdateRequired:
            return "update bundle requires a bridge/two-phase update"
        case let .unsupportedPlatform(currentPlatform, targetPlatform):
            return "update bundle targets \(targetPlatform); current platform is \(currentPlatform)"
        case let .guestActivationRequirementMismatch(requiresGuestActivation, hasGuestDeployArtifact):
            return "update bundle guest activation flag mismatch: requiresGuestActivation=\(requiresGuestActivation), hasGuestDeployArtifact=\(hasGuestDeployArtifact)"
        }
    }
}
