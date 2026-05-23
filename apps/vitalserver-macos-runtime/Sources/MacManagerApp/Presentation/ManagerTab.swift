import Foundation

enum ManagerTab: CaseIterable, Identifiable {
    case status
    case settings
    case update
    case log
    case info
    case advanced
    case dangerZone

    var id: Self { self }

    var title: String {
        switch self {
        case .status:
            return AppConstants.Labels.tabStatus
        case .settings:
            return AppConstants.Labels.tabSettings
        case .update:
            return AppConstants.Labels.tabUpdate
        case .log:
            return AppConstants.Labels.tabLog
        case .info:
            return AppConstants.Labels.tabInfo
        case .advanced:
            return AppConstants.Labels.tabAdvanced
        case .dangerZone:
            return AppConstants.Labels.tabDangerZone
        }
    }
}
