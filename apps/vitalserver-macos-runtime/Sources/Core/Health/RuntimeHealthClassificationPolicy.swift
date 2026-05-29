import Foundation

public enum RuntimeGuardrailState: Equatable, Sendable {
    case stable
    case transitional
    case failed
}

public enum RuntimeHealthClassificationPolicy {
    private static let transientContainerHealthStates = [
        "starting",
    ]

    public static func isFailingContainerHealth(_ health: String?) -> Bool {
        containerHealthState(health) == .failed
    }

    public static func containerHealthState(_ health: String?) -> RuntimeGuardrailState {
        guard let normalized = normalizedHealth(health),
              !normalized.isEmpty else {
            return .stable
        }
        if normalized == "healthy" {
            return .stable
        }
        if transientContainerHealthStates.contains(normalized) {
            return .transitional
        }
        return .failed
    }

    private static func normalizedHealth(_ value: String?) -> String? {
        value?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }
}
