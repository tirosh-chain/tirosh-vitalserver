enum LogSourceID: String, Hashable {
    case helperMessage
    case install
    case command
    case launcher
    case proxyOutput
    case proxyError
    case updateActivation
    case containers
}

struct LogSourceOption: Identifiable {
    let id: LogSourceID
    let title: String
}
