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
