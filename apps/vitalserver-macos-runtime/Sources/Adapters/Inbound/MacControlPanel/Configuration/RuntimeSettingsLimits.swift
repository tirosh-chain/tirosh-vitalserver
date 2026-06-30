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
        static let minimumBackupRetentionCount = 1
        static let maximumBackupRetentionCount = 30
        static let backupRetentionStep = 1
        static let minimumLogArchiveRetentionDays = 1
        static let maximumLogArchiveRetentionDays = 30
        static let logArchiveRetentionStepDays = 1
        static let minimumLogArchiveMaximumGiB = 1
        static let maximumLogArchiveMaximumGiB = 20
        static let logArchiveMaximumStepGiB = 1
        static let minimumRecorderIngressReplayBatchSize = 1
        static let maximumRecorderIngressReplayBatchSize = 100
        static let recorderIngressReplayBatchSizeStep = 1
        static let minimumRecorderIngressReplayMaxMiBPerSecond = 1
        static let maximumRecorderIngressReplayMaxMiBPerSecond = 100
        static let recorderIngressReplayThroughputStep = 5
        static let minimumVitalServerContainerMemoryLimitMiB = 512
        static let maximumVitalServerContainerMemoryLimitMiB = 32_768
        static let minimumRecorderIngressContainerMemoryLimitMiB = 128
        static let maximumRecorderIngressContainerMemoryLimitMiB = 4_096
        static let minimumRedisContainerMemoryLimitMiB = 256
        static let maximumRedisContainerMemoryLimitMiB = maximumMemoryGiB * 1024
        static let containerMemoryLimitStepMiB = 128
        static let containerMemoryLimitPercentStep = 1
        static let maximumCombinedContainerMemoryLimitPercent = 70
    }
}
