import Foundation

public protocol RuntimeClock {
    var now: Date { get }
}

public protocol RuntimeSleeper {
    func sleep(forTimeInterval interval: TimeInterval)
}
