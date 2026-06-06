import Interfaces

typealias RuntimeSection = Interfaces.RuntimeSection

extension RuntimeSection {
    static func visibleSections() -> [RuntimeSection] {
        visibleSections(testEnabled: GeneratedRelease.testEnabled)
    }

    static func primarySections() -> [RuntimeSection] {
        primarySections(testEnabled: GeneratedRelease.testEnabled)
    }

    static func utilitySections() -> [RuntimeSection] {
        utilitySections(testEnabled: GeneratedRelease.testEnabled)
    }

    static func overflowSections() -> [RuntimeSection] {
        overflowSections(testEnabled: GeneratedRelease.testEnabled)
    }

    static func sectionIsInOverflow(_ section: RuntimeSection) -> Bool {
        sectionIsInOverflow(section, testEnabled: GeneratedRelease.testEnabled)
    }

    var title: String {
        switch self {
        case .status:
            return AppConstants.Labels.sectionStatus
        case .recorders:
            return AppConstants.Labels.sectionRecorders
        case .beds:
            return AppConstants.Labels.sectionBeds
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
