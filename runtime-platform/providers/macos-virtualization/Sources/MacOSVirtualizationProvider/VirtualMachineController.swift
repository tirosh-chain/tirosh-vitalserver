import Foundation
@preconcurrency import Virtualization

public protocol VirtualMachineControlling: AnyObject {
    var canRequestStop: Bool { get }
    var observedState: VirtualMachineObservedState { get }
    func start(completion: @escaping (Result<Void, Error>) -> Void)
    func requestStop() throws
}

@available(macOS 13.0, *)
public final class AppleVirtualMachineController: VirtualMachineControlling, @unchecked Sendable {
    private let virtualMachine: VZVirtualMachine
    // VZVirtualMachine is bound to this queue when it is constructed. Every
    // VZ state read and operation must stay on that exact queue.
    private let guestRuntimeVirtualMachineOperationQueue: DispatchQueue
    private let guestRuntimeControlHostLocalHTTPBridge: GuestRuntimeControlHostLocalHTTPBridge
    private let guestPublicServiceHostLocalHTTPBridges: [GuestPublicServiceHostLocalHTTPBridge]
    private let guestBootConsoleCaptureFileHandle: FileHandle

    public init(
        virtualMachine: VZVirtualMachine,
        guestRuntimeVirtualMachineOperationQueue: DispatchQueue,
        guestRuntimeControlHostLocalHTTPBridge: GuestRuntimeControlHostLocalHTTPBridge,
        guestPublicServiceHostLocalHTTPBridges: [GuestPublicServiceHostLocalHTTPBridge],
        guestBootConsoleCaptureFileHandle: FileHandle
    ) {
        self.virtualMachine = virtualMachine
        self.guestRuntimeVirtualMachineOperationQueue = guestRuntimeVirtualMachineOperationQueue
        self.guestRuntimeControlHostLocalHTTPBridge = guestRuntimeControlHostLocalHTTPBridge
        self.guestPublicServiceHostLocalHTTPBridges = guestPublicServiceHostLocalHTTPBridges
        self.guestBootConsoleCaptureFileHandle = guestBootConsoleCaptureFileHandle
    }

    public var canRequestStop: Bool {
        guestRuntimeVirtualMachineOperationQueue.sync {
            virtualMachine.canRequestStop
        }
    }

    public var observedState: VirtualMachineObservedState {
        guestRuntimeVirtualMachineOperationQueue.sync {
            switch virtualMachine.state {
            case .starting:
                .starting
            case .running:
                .running
            case .stopping:
                .stopping
            case .stopped:
                .stopped
            default:
                .failed
            }
        }
    }

    public func start(completion: @escaping (Result<Void, Error>) -> Void) {
        let startCompletion = GuestRuntimeVirtualMachineStartCompletion(completion: completion)
        guestRuntimeVirtualMachineOperationQueue.async { [weak self, startCompletion] in
            guard let self else {
                startCompletion.complete(.failure(MacOSVirtualMachineConfigurationError.unavailable(
                    "Guest Runtime virtual machine controller is no longer available"
                )))
                return
            }
            self.virtualMachine.start { [weak self, startCompletion] result in
                guard let self else {
                    startCompletion.complete(.failure(MacOSVirtualMachineConfigurationError.unavailable(
                        "Guest Runtime virtual machine controller is no longer available"
                    )))
                    return
                }
                switch result {
                case .success:
                    do {
                        try self.guestRuntimeControlHostLocalHTTPBridge.start()
                        var startedGuestPublicServiceHostLocalHTTPBridges: [GuestPublicServiceHostLocalHTTPBridge] = []
                        do {
                            for bridge in self.guestPublicServiceHostLocalHTTPBridges {
                                try bridge.start()
                                startedGuestPublicServiceHostLocalHTTPBridges.append(bridge)
                            }
                        } catch {
                            startedGuestPublicServiceHostLocalHTTPBridges.forEach { $0.stop() }
                            self.guestRuntimeControlHostLocalHTTPBridge.stop()
                            throw error
                        }
                        startCompletion.complete(.success(()))
                    } catch {
                        // The VM started but the declared Host control transport
                        // did not. Request its explicit Guest shutdown and report
                        // the bridge failure; running a VM with an absent required
                        // control boundary is not a successful start.
                        try? self.virtualMachine.requestStop()
                        startCompletion.complete(.failure(error))
                    }
                case .failure(let error):
                    startCompletion.complete(.failure(error))
                }
            }
        }
    }

    public func requestStop() throws {
        guestPublicServiceHostLocalHTTPBridges.forEach { $0.stop() }
        guestRuntimeControlHostLocalHTTPBridge.stop()
        try guestRuntimeVirtualMachineOperationQueue.sync {
            try virtualMachine.requestStop()
        }
    }
}

// The lifecycle contract supplies one completion for one explicit start
// attempt. This reference makes that handoff safe while the VZ operation is
// executed on its dedicated serial queue.
private final class GuestRuntimeVirtualMachineStartCompletion: @unchecked Sendable {
    private let completion: (Result<Void, Error>) -> Void

    init(completion: @escaping (Result<Void, Error>) -> Void) {
        self.completion = completion
    }

    func complete(_ result: Result<Void, Error>) {
        completion(result)
    }
}
