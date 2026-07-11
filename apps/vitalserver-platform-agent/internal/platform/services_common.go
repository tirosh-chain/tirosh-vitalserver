package platform

import "github.com/tirosh/vitalserver-platform-agent/internal/contract"

func unavailableService(role, reason string) contract.PlatformServiceStatus {
	return contract.PlatformServiceStatus{Role: role, State: "unavailable", ReadError: &reason}
}

func failedService(role, state, reason string) contract.PlatformServiceStatus {
	return contract.PlatformServiceStatus{Role: role, State: state, ReadError: &reason}
}

func orderedServices(
	bindings map[string]*string,
	read func(role, serviceName string) contract.PlatformServiceStatus,
) []contract.PlatformServiceStatus {
	services := make([]contract.PlatformServiceStatus, 0, len(contract.PlatformServiceRoles))
	for _, role := range contract.PlatformServiceRoles {
		serviceName := bindings[role]
		if serviceName == nil {
			services = append(services, unavailableService(role, "service role is explicitly unavailable on this platform"))
			continue
		}
		services = append(services, read(role, *serviceName))
	}
	return services
}
