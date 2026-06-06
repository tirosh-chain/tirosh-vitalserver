import Foundation

public struct RuntimeInstallTransitionError: Error, Equatable, Sendable, CustomStringConvertible {
    public let state: String
    public let event: String
    public let reason: String

    public init<State, Event>(
        state: State,
        event: Event,
        reason: String = "invalid install transition"
    ) {
        self.state = String(describing: state)
        self.event = String(describing: event)
        self.reason = reason
    }

    public var description: String {
        "\(reason) state=\(state) event=\(event)"
    }
}
