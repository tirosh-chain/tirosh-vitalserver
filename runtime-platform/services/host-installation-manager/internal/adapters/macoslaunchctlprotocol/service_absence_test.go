package macoslaunchctlprotocol

import "testing"

func TestIsExplicitlyAbsentSystemServiceAcceptsKnownLegacyAndMacOS26Responses(t *testing.T) {
	serviceName := "com.tirosh.vitalserver.host-agent"
	for _, observation := range []struct {
		name       string
		exitCode   int
		diagnostic string
	}{
		{name: "legacy", exitCode: 3},
		{
			name:       "macos 26",
			exitCode:   113,
			diagnostic: "Bad request.\nCould not find service \"com.tirosh.vitalserver.host-agent\" in domain for system\n",
		},
	} {
		t.Run(observation.name, func(t *testing.T) {
			if !IsExplicitlyAbsentSystemService(observation.exitCode, observation.diagnostic, serviceName) {
				t.Fatalf("absence was not recognized: exit=%d diagnostic=%q", observation.exitCode, observation.diagnostic)
			}
		})
	}
}

func TestIsExplicitlyAbsentSystemServiceDoesNotAcceptAmbiguousMacOS26Failure(t *testing.T) {
	if IsExplicitlyAbsentSystemService(113, "Bad request.\nCould not find service \"another.service\" in domain for system\n", "com.tirosh.vitalserver.host-agent") {
		t.Fatal("a different missing service must not prove this declared service is absent")
	}
	if IsExplicitlyAbsentSystemService(113, "launchctl transport temporarily unavailable", "com.tirosh.vitalserver.host-agent") {
		t.Fatal("a generic launchctl failure must not prove a service is absent")
	}
}
