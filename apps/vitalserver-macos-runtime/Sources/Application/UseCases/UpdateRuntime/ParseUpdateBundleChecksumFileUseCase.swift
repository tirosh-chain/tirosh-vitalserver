import Domain

public struct ParseUpdateBundleChecksumFileUseCase {
    public init() {}

    public func parse(_ text: String) -> [String: String] {
        UpdateBundleChecksumFileParser.parse(text)
    }
}
