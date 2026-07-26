import Darwin
import Foundation
import Testing
@testable import MacOSVirtualizationProvider

private final class FakeController: VirtualMachineControlling {
    var canRequestStop: Bool
    var observedState: VirtualMachineObservedState
    var startResult: Result<Void, Error>
    var stopError: Error?
    private(set) var stopRequests = 0

    init(canRequestStop: Bool = true, observedState: VirtualMachineObservedState = .running, startResult: Result<Void, Error> = .success(()), stopError: Error? = nil) {
        self.canRequestStop = canRequestStop
        self.observedState = observedState
        self.startResult = startResult
        self.stopError = stopError
    }

    func start(completion: @escaping (Result<Void, Error>) -> Void) {
        completion(startResult)
    }

    func requestStop() throws {
        stopRequests += 1
        if let stopError {
            throw stopError
        }
    }
}

private final class MainQueueStartCompletion: @unchecked Sendable {
    let complete: (Result<Void, Error>) -> Void

    init(complete: @escaping (Result<Void, Error>) -> Void) {
        self.complete = complete
    }
}

private final class MainQueueStartCompletionController: VirtualMachineControlling {
    var canRequestStop: Bool { false }
    var observedState: VirtualMachineObservedState { .running }

    func start(completion: @escaping (Result<Void, Error>) -> Void) {
        let mainQueueCompletion = MainQueueStartCompletion(complete: completion)
        RunLoop.main.perform(inModes: [.default]) {
            mainQueueCompletion.complete(.success(()))
        }
    }

    func requestStop() throws {
        fatalError("main-queue start completion test must not request stop")
    }
}

private func request(_ action: String) -> ProviderLifecycleRequest {
    ProviderLifecycleRequest(schemaVersion: "v1", requestId: "request-1", providerId: "guest-vm", action: action)
}

@Test("C21 invocation keeps Host request and endpoint revision explicit")
func bridgeInvocationValidatesHostCorrelation() {
    let lifecycle = request("start")
    let invocation = PlatformProviderLifecycleInvocation(
        schemaVersion: "v1",
        providerKind: "macos-virtualization",
        requestId: "request-1",
        expectedGuestRuntimeControlEndpointRevision: 3,
        lifecycle: lifecycle
    )
    #expect(invocation.isValidForMacOSVirtualization)

    let mismatched = PlatformProviderLifecycleInvocation(
        schemaVersion: "v1",
        providerKind: "macos-virtualization",
        requestId: "different-request",
        expectedGuestRuntimeControlEndpointRevision: 3,
        lifecycle: lifecycle
    )
    #expect(!mismatched.isValidForMacOSVirtualization)
}

@Test("C32 byte relay preserves an established connection while a nonblocking socket waits")
func hostLocalHTTPBridgeDistinguishesSocketWaitingFromTerminalFailure() {
    #expect(HostLocalHTTPToGuestVirtioSocketByteRelaySocketResultPolicy.preservesEstablishedConnection(forSocketError: EAGAIN))
    #expect(HostLocalHTTPToGuestVirtioSocketByteRelaySocketResultPolicy.preservesEstablishedConnection(forSocketError: EWOULDBLOCK))
    #expect(HostLocalHTTPToGuestVirtioSocketByteRelaySocketResultPolicy.preservesEstablishedConnection(forSocketError: EINTR))
    #expect(!HostLocalHTTPToGuestVirtioSocketByteRelaySocketResultPolicy.preservesEstablishedConnection(forSocketError: ECONNRESET))
}

@Test("unconfigured virtual machine controller explicitly reports unavailable")
func unconfiguredBridgeReportsUnavailable() {
    let result = LifecycleExecutor(controller: nil, now: { Date(timeIntervalSince1970: 0) }).execute(request("start"))
    #expect(result.observedState == "unavailable")
    #expect(result.issue?.code == "macos-vm-not-configured")
}

@Test("configured start maps observed VZ controller state")
func startMapsObservedState() {
    let controller = FakeController(observedState: .running)
    let result = LifecycleExecutor(controller: controller, now: { Date(timeIntervalSince1970: 0) }).execute(request("start"))
    #expect(result.observedState == "running")
    #expect(result.issue == nil)
}

@Test("macOS VM start preserves the native failure detail")
func startPreservesNativeFailureDetail() {
    let nativeFailure = NSError(
        domain: "Virtualization",
        code: 91,
        userInfo: [NSLocalizedDescriptionKey: "declared Guest boot resource cannot start"]
    )
    let controller = FakeController(startResult: .failure(nativeFailure))
    let result = LifecycleExecutor(
        controller: controller,
        now: { Date(timeIntervalSince1970: 0) }
    ).execute(request("start"))

    #expect(result.observedState == "failed")
    #expect(result.issue?.code == "macos-vm-start-failed")
    #expect(result.issue?.message == "VZVirtualMachine start returned failure: declared Guest boot resource cannot start (domain=Virtualization, code=91)")
}

@Test("macOS VM start preserves native reason and underlying failure detail")
func startPreservesNativeFailureReasonAndUnderlyingFailureDetail() {
    let underlyingFailure = NSError(
        domain: "GuestStorage",
        code: 7,
        userInfo: [NSLocalizedDescriptionKey: "declared Guest root storage cannot attach"]
    )
    let nativeFailure = NSError(
        domain: "Virtualization",
        code: 91,
        userInfo: [
            NSLocalizedDescriptionKey: "declared Guest boot resource cannot start",
            NSLocalizedFailureReasonErrorKey: "required virtual machine resource is unavailable",
            NSUnderlyingErrorKey: underlyingFailure
        ]
    )
    let controller = FakeController(startResult: .failure(nativeFailure))
    let result = LifecycleExecutor(controller: controller).execute(request("start"))

    #expect(result.issue?.message?.contains("failureReason=required virtual machine resource is unavailable") == true)
    #expect(result.issue?.message?.contains("underlyingDomain=GuestStorage") == true)
    #expect(result.issue?.message?.contains("underlyingCode=7") == true)
    #expect(result.issue?.message?.contains("underlyingDescription=declared Guest root storage cannot attach") == true)
}

@Test("macOS VM start keeps the main run loop available for its completion")
func startObservesMainQueueCompletionWithoutManufacturingATimeout() {
    let controller = MainQueueStartCompletionController()
    let result = LifecycleExecutor(
        controller: controller,
        now: { Date(timeIntervalSince1970: 0) },
        startTimeout: 1
    ).execute(request("start"))

    #expect(result.observedState == "running")
    #expect(result.issue == nil)
}

@Test("stop does not claim stopped when controller only observes stopping")
func stopPreservesObservedState() {
    let controller = FakeController(observedState: .stopping)
    let result = LifecycleExecutor(controller: controller, now: { Date(timeIntervalSince1970: 0) }).execute(request("stop"))
    #expect(result.observedState == "stopping")
    #expect(controller.stopRequests == 1)
}
