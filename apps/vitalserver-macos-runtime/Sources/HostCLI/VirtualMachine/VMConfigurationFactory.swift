import Application
import Foundation
import HostAdapters
import HostInfrastructure

typealias VMConfigurationFactory = HostAdapters.VMConfigurationFactory
typealias VMConfigurationFactoryError = HostAdapters.VMConfigurationFactoryError

extension VMConfigurationFactory {
    static func hostCLI(fileStore: RuntimeFileReading = SystemRuntimeFileStore()) -> VMConfigurationFactory {
        VMConfigurationFactory(
            fileStore: fileStore,
            detached: ProcessInfo.processInfo.environment[Constants.Environment.detached] == "1",
            serialInput: .standardInput,
            serialOutput: .standardOutput
        )
    }
}
