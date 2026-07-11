//go:build windows

package agent

import "os"

func installationState(path string) string {
	info, err := os.Stat(path)
	if err != nil {
		if os.IsNotExist(err) {
			return "missing"
		}
		return "inspect-failed: " + err.Error()
	}
	if !info.Mode().IsRegular() {
		return "present"
	}
	return "executable"
}
