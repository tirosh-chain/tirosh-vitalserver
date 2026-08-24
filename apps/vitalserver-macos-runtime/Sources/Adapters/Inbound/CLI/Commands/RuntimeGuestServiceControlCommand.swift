import Contracts

public struct RuntimeGuestServiceControlCommand: Equatable, Sendable {
    public static let defaultGuestControlBaseURL =
        RuntimeGuestControlEndpointContract.baseURL(host: "127.0.0.1")

    public let service: String
    public let guestControlBaseURL: String

    public init(
        service: String,
        guestControlBaseURL: String = RuntimeGuestServiceControlCommand.defaultGuestControlBaseURL
    ) {
        self.service = service
        self.guestControlBaseURL = guestControlBaseURL
    }
}

public struct RuntimeGuestControlReadCommand: Equatable, Sendable {
    public let guestControlBaseURL: String

    public init(
        guestControlBaseURL: String = RuntimeGuestServiceControlCommand.defaultGuestControlBaseURL
    ) {
        self.guestControlBaseURL = guestControlBaseURL
    }
}
