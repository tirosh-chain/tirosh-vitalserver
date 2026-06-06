import Errors


public enum RuntimeSection: CaseIterable, Equatable, Identifiable {
    case status
    case recorders
    case beds
    case observability
    case log
    case settings
    case update
    case info
    case advanced
    case test
    case dangerZone

    public var id: Self { self }

    public static func visibleSections(testEnabled: Bool) -> [RuntimeSection] {
        allCases.filter { section in
            section != .test || testEnabled
        }
    }

    public static func primarySections(testEnabled: Bool) -> [RuntimeSection] {
        [.status, .recorders, .beds, .observability, .log, .settings, .update]
            .filter { visibleSections(testEnabled: testEnabled).contains($0) }
    }

    public static func utilitySections(testEnabled: Bool) -> [RuntimeSection] {
        [.advanced]
            .filter { visibleSections(testEnabled: testEnabled).contains($0) }
    }

    public static func overflowSections(testEnabled: Bool) -> [RuntimeSection] {
        [.info, .dangerZone, .test]
            .filter { visibleSections(testEnabled: testEnabled).contains($0) }
    }

    public static func sectionIsInOverflow(_ section: RuntimeSection, testEnabled: Bool) -> Bool {
        overflowSections(testEnabled: testEnabled).contains(section)
    }
}

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
