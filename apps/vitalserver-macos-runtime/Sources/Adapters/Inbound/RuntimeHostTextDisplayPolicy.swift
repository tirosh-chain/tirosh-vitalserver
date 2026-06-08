import RuntimeControl

public struct RuntimeHostTextDisplayPolicy {
    private let noDataText: String

    public init(noDataText: String) {
        self.noDataText = noDataText
    }

    public func displayText(_ result: RuntimeHostTextReadResult) -> String {
        switch result {
        case .loaded(let text), .failed(let text):
            return text
        case .loadedWithIssue(let text, let issue):
            return "\(issue)\n\n\(text)"
        case .missing(.message(let text)):
            return text
        case .missing(.noData):
            return noDataText
        }
    }
}
