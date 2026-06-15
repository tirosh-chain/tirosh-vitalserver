import Foundation

public enum RuntimeTestKitSessionStatePolicy {
    public static func normalizedState(_ state: String) -> String {
        state.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    public static func isActive(_ state: String) -> Bool {
        switch normalizedState(state) {
        case "running", "paused", "starting", "stopping":
            return true
        default:
            return false
        }
    }

    public static func isTerminal(_ state: String) -> Bool {
        switch normalizedState(state) {
        case "stopped", "failed":
            return true
        default:
            return false
        }
    }

    public static func preferredActiveSession(from sessions: [RuntimeTestKitSession]) -> RuntimeTestKitSession? {
        sessions.first { isActive($0.state) }
    }
}
