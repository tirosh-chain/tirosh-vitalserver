import Contracts
public enum RuntimeUpdateCompatibilityChecker {
    public static func check(
        manifest: UpdateBundleManifest,
        currentChannel: UpdateBundleChannel = .stable,
        currentPlatform: String? = nil
    ) throws {
        if manifest.channel != currentChannel {
            throw RuntimeUpdateCompatibilityError.unsupportedChannel(
                currentChannel: currentChannel,
                bundleChannel: manifest.channel
            )
        }

        if let currentPlatform,
           manifest.targetPlatform != currentPlatform {
            throw RuntimeUpdateCompatibilityError.unsupportedPlatform(
                currentPlatform: currentPlatform,
                targetPlatform: manifest.targetPlatform
            )
        }

        let hasGuestDeployArtifact = manifest.artifacts.contains { $0.type == .guestDeploy }
        if manifest.requiresGuestActivation != hasGuestDeployArtifact {
            throw RuntimeUpdateCompatibilityError.guestActivationRequirementMismatch(
                requiresGuestActivation: manifest.requiresGuestActivation,
                hasGuestDeployArtifact: hasGuestDeployArtifact
            )
        }
    }

}
