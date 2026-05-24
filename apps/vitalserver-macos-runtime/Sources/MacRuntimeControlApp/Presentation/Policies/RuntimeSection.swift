import Foundation

enum RuntimeSection: CaseIterable, Identifiable {
    case status
    case settings
    case update
    case events
    case test
    case log
    case info
    case advanced
    case dangerZone

    var id: Self { self }

    static func visibleSections(testEnabled: Bool = GeneratedRelease.testEnabled) -> [RuntimeSection] {
        allCases.filter { section in
            section != .test || testEnabled
        }
    }

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
        case .test:
            return AppConstants.Labels.sectionTest
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
