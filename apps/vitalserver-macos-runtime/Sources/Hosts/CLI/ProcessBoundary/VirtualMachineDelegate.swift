import Application
import Foundation
import OutboundAdapters
import Errors

extension VirtualMachineDelegate {
    static func hostCLI(
        pidFile: URL,
        lifecycleStore: RuntimeVMLifecycleStore,
        fileStore: RuntimeFileWriting = SystemRuntimeFileStore()
    ) -> VirtualMachineDelegate {
        VirtualMachineDelegate(
            pidFile: pidFile,
            fileStore: fileStore,
            writeLifecycle: { state, message in
                try lifecycleStore.write(state: state, message: message)
            }
        )
    }
}
