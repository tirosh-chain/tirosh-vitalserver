import Foundation
import RuntimeControl
import InboundAdapters
import Errors

@MainActor
protocol RuntimeControlLocalAPISettingsStoring: AnyObject {
    var runtimeControlPort: Int { get set }
}

@MainActor
final class UserDefaultsRuntimeControlLocalAPISettingsStore: RuntimeControlLocalAPISettingsStoring {
    static let shared = UserDefaultsRuntimeControlLocalAPISettingsStore()

    private let defaults: UserDefaults
    private let key = "runtimeControlPort"

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    var runtimeControlPort: Int {
        get {
            let stored = defaults.integer(forKey: key)
            guard Self.validPort(stored) else {
                return Int(RuntimeControlLocalAPIConstants.defaultPort)
            }
            return stored
        }
        set {
            guard Self.validPort(newValue) else {
                return
            }
            defaults.set(newValue, forKey: key)
        }
    }

    private static func validPort(_ port: Int) -> Bool {
        (1...65_535).contains(port)
    }
}

@MainActor
public final class RuntimeControlLocalAPISettingsCoordinator {
    private let store: any RuntimeControlLocalAPISettingsStoring
    public var onPortChanged: ((Int) -> Void)?

    init(store: any RuntimeControlLocalAPISettingsStoring) {
        self.store = store
    }

    public var runtimeControlPort: Int {
        store.runtimeControlPort
    }

    public func settingsWithLocalAPIPort(_ settings: RuntimeSettings) -> RuntimeSettings {
        var next = settings
        next.runtimeControlPort = runtimeControlPort
        return next
    }

    public func apply(settings: RuntimeSettings) {
        apply(port: settings.runtimeControlPort)
    }

    public func apply(port: Int) {
        guard (1...65_535).contains(port) else {
            return
        }
        let previousPort = store.runtimeControlPort
        store.runtimeControlPort = port
        guard previousPort != port else {
            return
        }
        onPortChanged?(port)
    }
}

public extension RuntimeControlLocalAPISettingsCoordinator {
    static func live() -> RuntimeControlLocalAPISettingsCoordinator {
        RuntimeControlLocalAPISettingsCoordinator(
            store: UserDefaultsRuntimeControlLocalAPISettingsStore.shared
        )
    }
}

extension RuntimeControlLocalAPISettingsCoordinator: RuntimeControlLocalAPISettingsApplying {}

@MainActor
final class InMemoryRuntimeControlLocalAPISettingsStore: RuntimeControlLocalAPISettingsStoring {
    var runtimeControlPort: Int

    init(runtimeControlPort: Int = Int(RuntimeControlLocalAPIConstants.defaultPort)) {
        self.runtimeControlPort = runtimeControlPort
    }
}
