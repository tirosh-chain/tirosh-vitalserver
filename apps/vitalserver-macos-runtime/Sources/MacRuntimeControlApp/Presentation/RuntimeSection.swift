import Foundation

enum RuntimeSection: CaseIterable, Identifiable {
    case status
    case settings
    case update
    case events
    case log
    case info
    case advanced
    case dangerZone

    var id: Self { self }

    var title: String {
        switch self {
        case .status:
            return AppConstants.Labels.sectionStatus
        case .settings:
            return AppConstants.Labels.sectionSettings
        case .update:
            return AppConstants.Labels.sectionUpdate
        case .events:
            return AppConstants.Labels.sectionEvents
        case .log:
            return AppConstants.Labels.sectionLog
        case .info:
            return AppConstants.Labels.sectionInfo
        case .advanced:
            return AppConstants.Labels.sectionAdvanced
        case .dangerZone:
            return AppConstants.Labels.sectionDangerZone
        }
    }
}
