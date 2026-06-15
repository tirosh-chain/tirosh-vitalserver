import Errors
extension AppConstants {
    enum Values {
        static let boolTrue = "true"
        static let boolFalse = "false"
        static let empty = "-"
        static let unlimited = "Unlimited"
    }

    enum Notifications {
        static let needsAttentionTitle = "VitalServer needs attention"
        static let criticalTitle = "VitalServer is critical"
        static let recoveredTitle = "VitalServer recovered"
        static let needsAttentionBody = "Open VitalServer Helper to review runtime health details."
        static let criticalBody = "VitalServer runtime requires administrator attention."
        static let recoveredBody = "All monitored runtime services are healthy again."
    }
}
