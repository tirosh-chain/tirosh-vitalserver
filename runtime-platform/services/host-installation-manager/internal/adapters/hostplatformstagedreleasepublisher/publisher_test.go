package hostplatformstagedreleasepublisher

import "testing"

func TestServiceDefinitionArchiveNameUsesManifestPlatform(t *testing.T) {
	for _, test := range []struct {
		platform string
		want     string
	}{
		{platform: "macos", want: "host-agent.plist"},
		{platform: "linux", want: "host-agent.service"},
		{platform: "windows", want: "host-agent.json"},
	} {
		got, err := serviceDefinitionArchiveName(test.platform, "host-agent")
		if err != nil || got != test.want {
			t.Fatalf("platform %s: got=%q err=%v want=%q", test.platform, got, err, test.want)
		}
	}
}
