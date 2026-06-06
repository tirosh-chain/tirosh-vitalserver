import Application
import Contracts
import Dispatch
import Foundation
import Virtualization

public final class VirtualMachineTerminationHandler {
    private let virtualMachine: VZVirtualMachine
    private let pidFile: URL
    private let writeLifecycle: (RuntimeVMLifecycleState, String) throws -> Void
    private let fileStore: RuntimeFileWriting
    private let exitProcess: (Int32) -> Never
    private let writeOutput: (String) -> Void
    private let writeError: (String) -> Void
    private var signalSources: [DispatchSourceSignal] = []
    private var stopRequested = false

    public init(
        virtualMachine: VZVirtualMachine,
        pidFile: URL,
        fileStore: RuntimeFileWriting,
        writeLifecycle: @escaping (RuntimeVMLifecycleState, String) throws -> Void,
        exitProcess: @escaping (Int32) -> Never = Foundation.exit,
        writeOutput: @escaping (String) -> Void = { print($0) },
        writeError: @escaping (String) -> Void = { fputs($0, stderr) }
    ) {
        self.virtualMachine = virtualMachine
        self.pidFile = pidFile
        self.fileStore = fileStore
        self.writeLifecycle = writeLifecycle
        self.exitProcess = exitProcess
        self.writeOutput = writeOutput
        self.writeError = writeError
    }

    public func start() {
        installSignalHandler(SIGTERM)
        installSignalHandler(SIGINT)
    }

    private func installSignalHandler(_ signalNumber: Int32) {
        signal(signalNumber, SIG_IGN)

        let source = DispatchSource.makeSignalSource(signal: signalNumber, queue: .main)
        source.setEventHandler { [weak self] in
            self?.requestGuestStop(signalNumber: signalNumber)
        }
        source.resume()
        signalSources.append(source)
    }

    private func requestGuestStop(signalNumber: Int32) {
        guard !stopRequested else {
            return
        }
        stopRequested = true

        writeOutput("received signal \(signalNumber); requesting vitalserver VM shutdown")
        do {
            try writeLifecycle(.stopping, "VM stop requested by signal \(signalNumber)")
        } catch {
            writeError("failed to write VM lifecycle stopping state: \(error)\n")
        }
        guard virtualMachine.canRequestStop else {
            handleUnavailableGuestStop()
            return
        }

        do {
            try virtualMachine.requestStop()
        } catch {
            writeError("failed to request guest shutdown: \(error)\n")
            markStopRequestFailed("VM guest stop request failed: \(error)")
        }
    }

    private func handleUnavailableGuestStop() {
        guard virtualMachine.canStop else {
            do {
                try writeLifecycle(.stopped, "VM process already stopped")
            } catch {
                writeError("failed to write VM lifecycle stopped state: \(error)\n")
            }
            ProcessState.removePidFile(pidFile, fileStore: fileStore)
            exitProcess(0)
        }

        markStopRequestFailed("VM guest stop request is unavailable")
    }

    private func markStopRequestFailed(_ message: String) {
        writeError("\(message)\n")
        do {
            try writeLifecycle(.failed, message)
        } catch {
            writeError("failed to write VM lifecycle failed state: \(error)\n")
        }
    }
}
