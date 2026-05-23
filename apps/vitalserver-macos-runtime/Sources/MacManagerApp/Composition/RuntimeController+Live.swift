import LocalManagement

extension RuntimeController {
    static func live() -> RuntimeController {
        RuntimeController(
            runtimeClient: LocalRuntimeClient(releaseInfo: .generated),
            healthNotifications: HealthNotificationCenter(),
            nativeShell: SystemRuntimeNativeShell()
        )
    }
}
