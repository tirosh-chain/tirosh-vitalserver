import Contracts

public enum RuntimeTestKitAvailabilityPolicy {
    public static func service(
        in status: RuntimeStatus,
        serviceName: String
    ) -> RuntimeContainerServiceObservation? {
        status.containerObservation?.composeServices.first { $0.service == serviceName }
    }

    public static func unavailableState(
        for service: RuntimeContainerServiceObservation?
    ) -> RuntimeTestKitState {
        guard let service else {
            return .stopped
        }

        switch service.state?.lowercased() {
        case "running", "restarting", "created":
            return .starting
        case "exited", "dead":
            return .failed
        default:
            return .stopped
        }
    }

    public static func unavailableMessage(
        for service: RuntimeContainerServiceObservation?,
        serviceName: String,
        apiBaseURL: String,
        healthIssue: String?
    ) -> String {
        let healthSuffix = healthIssue.map { " Health check: \($0)." } ?? ""
        guard let service else {
            return "TestKit container is not running. TestKit is optional and does not affect VitalServer.\(healthSuffix)"
        }

        let state = service.state ?? "not reported"
        let health = service.health ?? "not reported"
        return "TestKit container API is not reachable at \(apiBaseURL). Container state: \(state), health: \(health).\(healthSuffix)"
    }

    public static func unavailableReadIssues(
        for service: RuntimeContainerServiceObservation?,
        serviceName: String,
        message: String,
        healthIssue: String?
    ) -> [RuntimeTestKitReadIssue] {
        var issues = [
            RuntimeTestKitReadIssue(source: "testKitAPI", message: message),
        ]
        if let healthIssue {
            issues.append(RuntimeTestKitReadIssue(source: "testKitAPI.health", message: healthIssue))
        }
        guard let service else {
            issues.append(RuntimeTestKitReadIssue(
                source: "containerService",
                message: "TestKit container service observation is missing for \(serviceName)."
            ))
            return issues
        }
        if service.state == nil {
            issues.append(RuntimeTestKitReadIssue(
                source: "containerService.state",
                message: "TestKit container service state is not reported for \(serviceName)."
            ))
        }
        if service.health == nil {
            issues.append(RuntimeTestKitReadIssue(
                source: "containerService.health",
                message: "TestKit container service health is not reported for \(serviceName)."
            ))
        }
        return issues
    }
}
