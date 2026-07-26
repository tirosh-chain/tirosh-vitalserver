public struct RuntimeGuestServiceControlRequest: Codable, Equatable, Sendable {
    public let service: String
    public let guestControlBaseURL: String?

    public init(service: String, guestControlBaseURL: String? = nil) {
        self.service = service
        self.guestControlBaseURL = guestControlBaseURL
    }
}

public typealias RuntimeGuestServiceRestartRequest = RuntimeGuestServiceControlRequest
