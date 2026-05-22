import Foundation

public enum RuntimeUpdateCompatibilityError: Error, Equatable, CustomStringConvertible {
    case updaterTooOld(currentVersion: String, minimumVersion: String)
    case twoPhaseUpdateRequired
    case guestActivationRequirementMismatch(requiresGuestActivation: Bool, hasGuestDeployArtifact: Bool)

    public var description: String {
        switch self {
        case let .updaterTooOld(currentVersion, minimumVersion):
            return "update bundle requires updater \(minimumVersion) or newer; current updater is \(currentVersion)"
        case .twoPhaseUpdateRequired:
            return "update bundle requires a bridge/two-phase update"
        case let .guestActivationRequirementMismatch(requiresGuestActivation, hasGuestDeployArtifact):
            return "update bundle guest activation flag mismatch: requiresGuestActivation=\(requiresGuestActivation), hasGuestDeployArtifact=\(hasGuestDeployArtifact)"
        }
    }
}

public enum RuntimeUpdateCompatibilityChecker {
    public static func check(
        manifest: UpdateBundleManifest,
        currentUpdaterVersion: String,
        allowTwoPhaseUpdate: Bool = false
    ) throws {
        if let minimumVersion = manifest.minUpdaterVersion,
           compareVersions(currentUpdaterVersion, minimumVersion) == .orderedAscending {
            throw RuntimeUpdateCompatibilityError.updaterTooOld(
                currentVersion: currentUpdaterVersion,
                minimumVersion: minimumVersion
            )
        }

        if manifest.requiresTwoPhaseUpdate, !allowTwoPhaseUpdate {
            throw RuntimeUpdateCompatibilityError.twoPhaseUpdateRequired
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
