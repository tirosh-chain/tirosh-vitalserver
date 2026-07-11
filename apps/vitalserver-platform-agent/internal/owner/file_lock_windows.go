//go:build windows

package owner

import (
	"fmt"
	"os"

	"golang.org/x/sys/windows"
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
	overlapped := &windows.Overlapped{}
	if err := windows.LockFileEx(
		windows.Handle(file.Fd()),
		windows.LOCKFILE_EXCLUSIVE_LOCK,
		0,
		1,
		0,
		overlapped,
	); err != nil {
		return LeaseError{Kind: LeaseWrite, Message: fmt.Sprintf("operation lease lock failed path=%s: %v", path, err)}
	}
	defer func() {
		if unlockErr := windows.UnlockFileEx(windows.Handle(file.Fd()), 0, 1, 0, overlapped); unlockErr != nil && resultErr == nil {
			resultErr = LeaseError{Kind: LeaseWrite, Message: fmt.Sprintf("operation lease unlock failed path=%s: %v", path, unlockErr)}
		}
	}()
	return work()
}
