import Contracts
import Foundation
import Errors

public enum RuntimeUpdateCompatibilityChecker {
    public static func check(
        manifest: UpdateBundleManifest,
        currentUpdaterVersion: String,
        currentChannel: UpdateBundleChannel = .stable,
        currentPlatform: String? = nil,
        allowTwoPhaseUpdate: Bool = false
    ) throws {
        if let minimumVersion = manifest.minUpdaterVersion,
           compareVersions(currentUpdaterVersion, minimumVersion) == .orderedAscending {
            throw RuntimeUpdateCompatibilityError.updaterTooOld(
                currentVersion: currentUpdaterVersion,
                minimumVersion: minimumVersion
            )
        }

        if manifest.channel != currentChannel {
            throw RuntimeUpdateCompatibilityError.unsupportedChannel(
                currentChannel: currentChannel,
                bundleChannel: manifest.channel
            )
        }

        if manifest.requiresTwoPhaseUpdate, !allowTwoPhaseUpdate {
            throw RuntimeUpdateCompatibilityError.twoPhaseUpdateRequired
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

    private static func compareVersions(_ lhs: String, _ rhs: String) -> ComparisonResult {
        let lhsParts = versionParts(lhs)
        let rhsParts = versionParts(rhs)
        let count = max(lhsParts.count, rhsParts.count)

        for index in 0..<count {
            let left = index < lhsParts.count ? lhsParts[index] : .number(0)
            let right = index < rhsParts.count ? rhsParts[index] : .number(0)
            let result = compareVersionPart(left, right)
            if result != .orderedSame {
                return result
            }
        }

        return .orderedSame
    }

    private enum VersionPart: Equatable {
        case number(Int)
        case text(String)
    }

    private static func versionParts(_ value: String) -> [VersionPart] {
        value
            .split { character in
                character == "." || character == "-" || character == "_"
            }
            .map { part in
                if let number = Int(part) {
                    return .number(number)
                }
                return .text(String(part))
            }
    }

    private static func compareVersionPart(_ lhs: VersionPart, _ rhs: VersionPart) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (.number(left), .number(right)):
            if left < right { return .orderedAscending }
            if left > right { return .orderedDescending }
            return .orderedSame
        case let (.text(left), .text(right)):
            return left.compare(right, options: [.numeric])
        case (.number, .text):
            return .orderedDescending
        case (.text, .number):
            return .orderedAscending
        }
    }
}
