import Foundation

enum RuntimeSection: CaseIterable, Identifiable {
    case status
    case recorders
    case settings
    case update
    case observability
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
        case .recorders:
            return AppConstants.Labels.sectionRecorders
        case .settings:
            return AppConstants.Labels.sectionSettings
        case .update:
            return AppConstants.Labels.sectionUpdate
        case .observability:
            return AppConstants.Labels.sectionObservability
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
