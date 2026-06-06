public enum Command: String {
    case initialize = "init"
    case start
    case stop
    case status
    case network
    case interfaces
    case configure
    case runtime
    case clean
    case version
    case help

    public static let helpAliases = ["--help", "-h"]

    public static func parse(_ value: String) -> Command? {
        if helpAliases.contains(value) {
            return .help
        }
        return Command(rawValue: value)
    }
}
