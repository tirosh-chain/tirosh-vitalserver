//go:build !windows

package owner

import (
	"fmt"
	"os"

	"golang.org/x/sys/unix"
)

func withExclusiveFileLock(path string, work func() error) (resultErr error) {
	file, err := os.OpenFile(path, os.O_CREATE|os.O_RDWR, 0o600)
	if err != nil {
		return LeaseError{Kind: LeaseWrite, Message: fmt.Sprintf("operation lease lock open failed path=%s: %v", path, err)}
	}
	defer func() {
		if closeErr := file.Close(); closeErr != nil && resultErr == nil {
			resultErr = LeaseError{Kind: LeaseWrite, Message: fmt.Sprintf("operation lease lock close failed path=%s: %v", path, closeErr)}
		}
	}()
	if err := unix.Flock(int(file.Fd()), unix.LOCK_EX); err != nil {
		return LeaseError{Kind: LeaseWrite, Message: fmt.Sprintf("operation lease lock failed path=%s: %v", path, err)}
	}
	defer func() {
		if unlockErr := unix.Flock(int(file.Fd()), unix.LOCK_UN); unlockErr != nil && resultErr == nil {
			resultErr = LeaseError{Kind: LeaseWrite, Message: fmt.Sprintf("operation lease unlock failed path=%s: %v", path, unlockErr)}
		}
	}()
	return work()
}
