import Application
import Foundation
import OutboundAdapters
import Errors

extension VirtualMachineDelegate {
    static func hostCLI(
        pidFile: URL,
        lifecycleWriter: any RuntimeVMLifecycleResourceWriting,
        fileStore: RuntimeFileWriting = SystemRuntimeFileStore()
    ) -> VirtualMachineDelegate {
        VirtualMachineDelegate(
            pidFile: pidFile,
            fileStore: fileStore,
            writeLifecycle: { state, message in
                try lifecycleWriter.writeVMLifecycleResource(
                    state: state,
                    operation: nil,
                    terminalReason: nil,
                    message: message,
                    bootWindowSeconds: nil
                )
            }
        )
    }
}
