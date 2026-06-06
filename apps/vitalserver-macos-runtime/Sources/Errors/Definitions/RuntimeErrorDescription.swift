public enum RuntimeErrorDescription {
    public static func describe(_ error: Error) -> String {
        String(describing: error)
    }
}
