import Errors
public enum RuntimeServiceControlCommand: Equatable, Sendable {
    case repairAll
    case repairProxy
    case startAll
    case stopAll
}
