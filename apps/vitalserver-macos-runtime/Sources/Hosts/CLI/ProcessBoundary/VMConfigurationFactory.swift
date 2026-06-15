import Application
import Foundation
import Bootstrap
import OutboundAdapters
import Errors

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
