public protocol RuntimeStatusContainerStateVocabulary {
    var notReportedText: String { get }

    func containerHealthText(_ health: String) -> String
    func containerStateText(_ state: String) -> String
}
