// Package macoslaunchctlprotocol decodes the narrow, versioned launchctl
// response that says one declared system service does not exist. It is an
// adapter protocol, not an installation-state policy.
package macoslaunchctlprotocol

import "strings"

const macOS26MissingSystemServiceExitStatus = 113

// IsExplicitlyAbsentSystemService recognizes only launchctl's established
// no-service responses for the exact declared system service. Legacy macOS
// releases use exit status 3. macOS 26 uses status 113 and includes the
// service label in its diagnostic. A generic status 113 must remain a command
// failure instead of being reclassified as an absent service.
func IsExplicitlyAbsentSystemService(exitCode int, diagnostic string, serviceName string) bool {
	if exitCode == 3 {
		return true
	}
	if exitCode != macOS26MissingSystemServiceExitStatus {
		return false
	}
	expectedResponse := `Could not find service "` + serviceName + `" in domain for system`
	return strings.Contains(diagnostic, expectedResponse)
}
