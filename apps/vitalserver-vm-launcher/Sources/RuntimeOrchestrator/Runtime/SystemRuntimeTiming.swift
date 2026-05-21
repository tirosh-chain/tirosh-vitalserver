import Foundation
import RuntimeCore

struct SystemRuntimeClock: RuntimeClock {
    var now: Date {
        Date()
    }
}

struct ThreadRuntimeSleeper: RuntimeSleeper {
    func sleep(forTimeInterval interval: TimeInterval) {
        Thread.sleep(forTimeInterval: interval)
    }
}
