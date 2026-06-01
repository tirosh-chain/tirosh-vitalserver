import Dispatch
import Foundation
import Core
import HostInfrastructure
import Virtualization

final class VirtualMachineTerminationHandler {
    private let virtualMachine: VZVirtualMachine
    private let pidFile: URL
    private let lifecycleStore: RuntimeVMLifecycleStore
    private let fileStore: RuntimeFileWriting
    private var signalSources: [DispatchSourceSignal] = []
    private var stopRequested = false

    init(
        virtualMachine: VZVirtualMachine,
        pidFile: URL,
        lifecycleStore: RuntimeVMLifecycleStore,
        fileStore: RuntimeFileWriting = SystemRuntimeFileStore()
    ) {
        self.virtualMachine = virtualMachine
        self.pidFile = pidFile
        self.lifecycleStore = lifecycleStore
        self.fileStore = fileStore
    }

    func start() {
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

        print("received signal \(signalNumber); requesting vitalserver VM shutdown")
        do {
            try lifecycleStore.write(state: .stopping, message: "VM stop requested by signal \(signalNumber)")
        } catch {
            fputs("failed to write VM lifecycle stopping state: \(error)\n", stderr)
        }
        guard virtualMachine.canRequestStop else {
            handleUnavailableGuestStop()
            return
        }

        do {
            try virtualMachine.requestStop()
        } catch {
            fputs("failed to request guest shutdown: \(error)\n", stderr)
            markStopRequestFailed("VM guest stop request failed: \(error)")
        }
    }

    private func handleUnavailableGuestStop() {
        guard virtualMachine.canStop else {
            do {
                try lifecycleStore.write(state: .stopped, message: "VM process already stopped")
            } catch {
                fputs("failed to write VM lifecycle stopped state: \(error)\n", stderr)
            }
            ProcessState.removePidFile(pidFile, fileStore: fileStore)
            Foundation.exit(0)
        }

        markStopRequestFailed("VM guest stop request is unavailable")
    }

    private func markStopRequestFailed(_ message: String) {
        fputs("\(message)\n", stderr)
        do {
            try lifecycleStore.write(state: .failed, message: message)
        } catch {
            fputs("failed to write VM lifecycle failed state: \(error)\n", stderr)
        }
    }
}
