import Foundation

enum RuntimeSection: CaseIterable, Identifiable {
    case status
    case recorders
    case observability
    case log
    case settings
    case update
    case info
    case advanced
    case test
    case dangerZone

    var id: Self { self }

    static func visibleSections(testEnabled: Bool = GeneratedRelease.testEnabled) -> [RuntimeSection] {
        allCases.filter { section in
            section != .test || testEnabled
        }
    }

    static func primarySections(testEnabled: Bool = GeneratedRelease.testEnabled) -> [RuntimeSection] {
        [.status, .recorders, .observability, .log, .settings, .update]
            .filter { visibleSections(testEnabled: testEnabled).contains($0) }
    }

    static func utilitySections(testEnabled: Bool = GeneratedRelease.testEnabled) -> [RuntimeSection] {
        [.advanced]
            .filter { visibleSections(testEnabled: testEnabled).contains($0) }
    }

    static func overflowSections(testEnabled: Bool = GeneratedRelease.testEnabled) -> [RuntimeSection] {
        [.info, .dangerZone, .test]
            .filter { visibleSections(testEnabled: testEnabled).contains($0) }
    }

    static func sectionIsInOverflow(_ section: RuntimeSection, testEnabled: Bool = GeneratedRelease.testEnabled) -> Bool {
        overflowSections(testEnabled: testEnabled).contains(section)
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
