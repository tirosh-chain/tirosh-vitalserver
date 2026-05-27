import Dispatch
import Foundation
import Core
import HostInfrastructure
import Virtualization

final class VirtualMachineTerminationHandler {
    private let virtualMachine: VZVirtualMachine
    private let pidFile: URL
    private let fileStore: RuntimeFileWriting
    private var signalSources: [DispatchSourceSignal] = []
    private var stopRequested = false

    init(
        virtualMachine: VZVirtualMachine,
        pidFile: URL,
        fileStore: RuntimeFileWriting = SystemRuntimeFileStore()
    ) {
        self.virtualMachine = virtualMachine
        self.pidFile = pidFile
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
        guard virtualMachine.canRequestStop else {
            forceStop()
            return
        }

        do {
            try virtualMachine.requestStop()
        } catch {
            fputs("failed to request guest shutdown: \(error)\n", stderr)
            forceStop()
        }
    }

    private func forceStop() {
        guard virtualMachine.canStop else {
            ProcessState.removePidFile(pidFile, fileStore: fileStore)
            Foundation.exit(0)
        }

        fputs("forcing vitalserver VM stop\n", stderr)
        virtualMachine.stop { [pidFile] error in
            if let error {
                fputs("failed to stop VM: \(error)\n", stderr)
                Foundation.exit(1)
            }
            ProcessState.removePidFile(pidFile, fileStore: SystemRuntimeFileStore())
            Foundation.exit(0)
        }
    }
}
