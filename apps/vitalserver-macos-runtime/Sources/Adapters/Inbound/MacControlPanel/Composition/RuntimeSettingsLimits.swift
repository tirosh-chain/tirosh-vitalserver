import Foundation
import Errors

extension AppConstants {
    enum SettingsLimits {
        static let minimumCPUCount = 7
        static let maximumCPUCount = 64
        static let minimumSystemCPUCountForDynamicLimit = 8
        static var maximumAllowedCPUCount: Int {
            let systemCPUCount = ProcessInfo.processInfo.processorCount
            guard systemCPUCount >= minimumSystemCPUCountForDynamicLimit else {
                return minimumCPUCount
            }
            return min(maximumCPUCount, systemCPUCount)
        }
        static let defaultDiskGiB = 32
        static let minimumDiskGiB = 4
        static let maximumDiskGiB = 512
        static let diskStepGiB = 4
        static let minimumMemoryGiB = 4
        static let maximumMemoryGiB = 64
        static let reservedHostMemoryGiB = 4
        static let memoryStepGiB = 4
        static var maximumAllowedMemoryGiB: Int {
            let physicalMemoryGiB = Int(ProcessInfo.processInfo.physicalMemory / 1_073_741_824)
            let hostAwareMaximum = physicalMemoryGiB - reservedHostMemoryGiB
            let cappedMaximum = min(maximumMemoryGiB, hostAwareMaximum)
            let steppedMaximum = (cappedMaximum / memoryStepGiB) * memoryStepGiB
            return max(minimumMemoryGiB, steppedMaximum)
        }
        static let minimumRedisBackupRetentionCount = 1
        static let maximumRedisBackupRetentionCount = 30
        static let redisBackupRetentionStep = 1
    }
}
