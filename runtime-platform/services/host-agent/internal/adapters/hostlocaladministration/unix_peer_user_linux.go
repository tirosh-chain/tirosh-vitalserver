//go:build linux

package hostlocaladministration

import (
	"fmt"
	"net"

	"golang.org/x/sys/unix"
)

func unixPeerUserID(connection net.Conn) (int, error) {
	unixConnection, ok := connection.(*net.UnixConn)
	if !ok {
		return 0, fmt.Errorf("local administration peer is not a Unix connection")
	}
	raw, err := unixConnection.SyscallConn()
	if err != nil {
		return 0, fmt.Errorf("access local administration peer socket: %w", err)
	}
	var userID int
	var peerErr error
	if err := raw.Control(func(fileDescriptor uintptr) {
		credentials, err := unix.GetsockoptUcred(int(fileDescriptor), unix.SOL_SOCKET, unix.SO_PEERCRED)
		if err != nil {
			peerErr = err
			return
		}
		userID = int(credentials.Uid)
	}); err != nil {
		return 0, fmt.Errorf("read local administration peer credentials: %w", err)
	}
	if peerErr != nil {
		return 0, fmt.Errorf("read local administration peer credentials: %w", peerErr)
	}
	return userID, nil
}
