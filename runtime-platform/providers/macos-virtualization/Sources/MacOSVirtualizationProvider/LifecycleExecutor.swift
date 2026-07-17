import Foundation

public final class LifecycleExecutor {
    private let controller: (any VirtualMachineControlling)?
    private let now: () -> Date
    private let startTimeout: TimeInterval

    public init(controller: (any VirtualMachineControlling)?, now: @escaping () -> Date = Date.init, startTimeout: TimeInterval = 30) {
        self.controller = controller
        self.now = now
        self.startTimeout = startTimeout
    }

    public func execute(_ request: ProviderLifecycleRequest) -> ProviderLifecycleResult {
        guard request.schemaVersion == "v1" else {
            return failure(request, code: "unsupported-schema-version", message: "provider request schemaVersion must be v1", retryable: false)
        }
        guard let controller else {
            return unavailable(request, code: "macos-vm-not-configured", message: "no macOS VZVirtualMachine controller has been configured")
        }
        switch request.action {
        case "start":
            return start(request, controller: controller)
        case "stop":
            return stop(request, controller: controller)
        case "reboot":
            return unavailable(request, code: "macos-vm-reboot-not-configured", message: "reboot requires a configured stop-observation and restart controller")
        default:
            return failure(request, code: "unsupported-lifecycle-action", message: "provider action must be start, stop, or reboot", retryable: false)
        }
    }

    private func start(_ request: ProviderLifecycleRequest, controller: any VirtualMachineControlling) -> ProviderLifecycleResult {
        guard let completion = waitForMacOSVirtualMachineStartCompletion(controller) else {
            return failure(request, code: "macos-vm-start-timed-out", message: "VZVirtualMachine start did not complete before the provider timeout", retryable: true)
        }
        switch completion {
        case .success:
            return observed(request, state: controller.observedState)
        case .failure(let error):
            return failure(
                request,
                code: "macos-vm-start-failed",
                message: macOSVirtualMachineStartFailureMessage(error),
                retryable: true
            )
        }
    }

    private func macOSVirtualMachineStartFailureMessage(_ error: Error) -> String {
        let nativeError = error as NSError
        var diagnostic = "VZVirtualMachine start returned failure: \(nativeError.localizedDescription) (domain=\(nativeError.domain), code=\(nativeError.code))"
        if let failureReason = nativeError.localizedFailureReason, !failureReason.isEmpty {
            diagnostic += " (failureReason=\(failureReason))"
        }
        if let underlyingError = nativeError.userInfo[NSUnderlyingErrorKey] as? NSError {
            diagnostic += " (underlyingDomain=\(underlyingError.domain), underlyingCode=\(underlyingError.code), underlyingDescription=\(underlyingError.localizedDescription))"
        }
        return diagnostic
    }

    private func waitForMacOSVirtualMachineStartCompletion(
        _ controller: any VirtualMachineControlling
    ) -> Result<Void, Error>? {
        let completionSignal = DispatchSemaphore(value: 0)
        let completionLock = NSLock()
        var completion: Result<Void, Error>?
        controller.start { result in
            completionLock.lock()
            completion = result
            completionLock.unlock()
            completionSignal.signal()
        }

        let deadline = Date().addingTimeInterval(startTimeout)
        while Date() < deadline {
            if completionSignal.wait(timeout: .now()) == .success {
                completionLock.lock()
                defer { completionLock.unlock() }
                return completion
            }
            // VZVirtualMachine may dispatch its start completion to the main
            // run loop. A blocking semaphore wait on this process's main
            // thread would then manufacture a timeout despite a valid Guest
            // configuration, so keep the provider event loop serviceable
            // while observing the declared timeout.
            RunLoop.current.run(until: min(Date().addingTimeInterval(0.01), deadline))
        }
        if completionSignal.wait(timeout: .now()) == .success {
            completionLock.lock()
            defer { completionLock.unlock() }
            return completion
        }
        return nil
    }

    private func stop(_ request: ProviderLifecycleRequest, controller: any VirtualMachineControlling) -> ProviderLifecycleResult {
        guard controller.canRequestStop else {
            return unavailable(request, code: "macos-vm-stop-unavailable", message: "VZVirtualMachine cannot accept a stop request")
        }
        do {
            try controller.requestStop()
            return observed(request, state: controller.observedState)
        } catch {
            return failure(request, code: "macos-vm-stop-failed", message: "VZVirtualMachine stop request failed", retryable: true)
        }
    }

    private func observed(_ request: ProviderLifecycleRequest, state: VirtualMachineObservedState) -> ProviderLifecycleResult {
        if state == .failed {
            return failure(request, code: "macos-vm-observation-failed", message: "VZVirtualMachine reported an unsupported failure state", retryable: true)
        }
        return ProviderLifecycleResult(requestId: request.requestId, providerId: request.providerId, observedState: state.contractValue, observedAt: timestamp())
    }

    private func unavailable(_ request: ProviderLifecycleRequest, code: String, message: String) -> ProviderLifecycleResult {
        ProviderLifecycleResult(
            requestId: request.requestId,
            providerId: request.providerId,
            observedState: "unavailable",
            observedAt: timestamp(),
            issue: ProviderIssue(code: code, message: message, retryable: true, dependency: "macos-virtualization")
        )
    }

    private func failure(_ request: ProviderLifecycleRequest, code: String, message: String, retryable: Bool) -> ProviderLifecycleResult {
        ProviderLifecycleResult(
            requestId: request.requestId,
            providerId: request.providerId,
            observedState: "failed",
            observedAt: timestamp(),
            issue: ProviderIssue(code: code, message: message, retryable: retryable, dependency: "macos-virtualization")
        )
    }

    private func timestamp() -> String {
        ISO8601DateFormatter().string(from: now())
    }
}
