import Darwin
import Foundation

public struct ProcessUserIdentity: Equatable, Sendable {
    public let uid: UInt32
    public let euid: UInt32

    public init(uid: UInt32, euid: UInt32) {
        self.uid = uid
        self.euid = euid
    }
}

public struct SystemProcessUserIdentityReader {
    public init() {}

    public func read() -> ProcessUserIdentity {
        ProcessUserIdentity(uid: getuid(), euid: geteuid())
    }
}
