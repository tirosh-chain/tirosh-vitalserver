import Foundation

public struct RuntimeUninstallTransitionError: Error, Equatable, Sendable, CustomStringConvertible {
    public let state: String
    public let event: String

    public init<State, Event>(state: State, event: Event) {
        self.state = String(describing: state)
        self.event = String(describing: event)
    }

    public var description: String {
        "invalid uninstall transition state=\(state) event=\(event)"
    }
}
