//go:build !windows

package owner

import "os"

func replaceFile(source, destination string) error {
	return os.Rename(source, destination)
}
