enum Command: String {
    case initialize = "init"
    case start
    case stop
    case status
    case interfaces
    case clean
    case version
    case help

    static let helpAliases = ["--help", "-h"]

    static func parse(_ value: String) -> Command? {
        if helpAliases.contains(value) {
            return .help
        }
        return Command(rawValue: value)
    }
}
