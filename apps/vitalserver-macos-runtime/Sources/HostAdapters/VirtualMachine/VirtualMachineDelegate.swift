import Application
import Contracts
import Foundation
import Virtualization

public final class VirtualMachineDelegate: NSObject, VZVirtualMachineDelegate {
    public let pidFile: URL
    private let writeLifecycle: (RuntimeVMLifecycleState, String) throws -> Void
    private let fileStore: RuntimeFileWriting
    private let exitProcess: (Int32) -> Never
    private let writeError: (String) -> Void

    public init(
        pidFile: URL,
        fileStore: RuntimeFileWriting,
        writeLifecycle: @escaping (RuntimeVMLifecycleState, String) throws -> Void,
        exitProcess: @escaping (Int32) -> Never = Foundation.exit,
        writeError: @escaping (String) -> Void = { fputs($0, stderr) }
    ) {
        self.pidFile = pidFile
        self.fileStore = fileStore
        self.writeLifecycle = writeLifecycle
        self.exitProcess = exitProcess
        self.writeError = writeError
    }

    // Clean up process state when the guest shuts itself down.
    public func guestDidStop(_ virtualMachine: VZVirtualMachine) {
        do {
            try writeLifecycle(.stopped, "VM guest stopped")
        } catch {
            writeError("failed to write VM lifecycle stopped state: \(error)\n")
        }
        ProcessState.removePidFile(pidFile, fileStore: fileStore)
        exitProcess(0)
    }
}
