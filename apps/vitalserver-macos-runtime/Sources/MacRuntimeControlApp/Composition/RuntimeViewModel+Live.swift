import MacHostRuntimeAdapter

extension RuntimeViewModel {
    static func live() -> RuntimeViewModel {
        let client = MacHostRuntimeClient(releaseInfo: .generated)
        return RuntimeViewModel(
            controlClient: client,
            hostClient: client,
            healthNotifications: HealthNotificationCenter(),
            nativeShell: SystemRuntimeNativeShell()
        )
    }
}
