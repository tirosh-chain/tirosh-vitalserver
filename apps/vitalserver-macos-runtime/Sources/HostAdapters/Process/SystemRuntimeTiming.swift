import Foundation
import Application

public struct SystemRuntimeClock: RuntimeClock {
    public init() {}

    public var now: Date {
        Date()
    }
}

public struct ThreadRuntimeSleeper: RuntimeSleeper {
    public init() {}

    public func sleep(forTimeInterval interval: TimeInterval) {
        Thread.sleep(forTimeInterval: interval)
    }
}
