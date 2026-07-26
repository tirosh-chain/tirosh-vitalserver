//go:build linux

// Package guestproductreleasecontrolvirtiotransport owns the C59 Linux
// AF_VSOCK listener. It transports bytes only: C59's HTTP/API layer owns
// release commands, and C32 owns the matching Host-loopback listener.
package guestproductreleasecontrolvirtiotransport

import (
	"fmt"
	"net"
	"sync"
	"time"

	"golang.org/x/sys/unix"
)

// ListenGuestProductReleaseManagerControlVirtioSocket opens the declared C59
// Guest listener. It never opens TCP, discovers a Host address, or selects a
// port from runtime state.
func ListenGuestProductReleaseManagerControlVirtioSocket(port uint32) (net.Listener, error) {
	if port == 0 || port > uint32(^uint16(0)) {
		return nil, fmt.Errorf("Guest Product Release Manager control virtio-socket port must be between 1 and 65535")
	}
	fileDescriptor, err := unix.Socket(unix.AF_VSOCK, unix.SOCK_STREAM|unix.SOCK_CLOEXEC, 0)
	if err != nil {
		return nil, fmt.Errorf("Guest Product Release Manager control virtio-socket cannot be created: %w", err)
	}
	closeFileDescriptor := true
	defer func() {
		if closeFileDescriptor {
			_ = unix.Close(fileDescriptor)
		}
	}()
	if err := unix.Bind(fileDescriptor, &unix.SockaddrVM{CID: unix.VMADDR_CID_ANY, Port: port}); err != nil {
		return nil, fmt.Errorf("Guest Product Release Manager control virtio-socket cannot bind port %d: %w", port, err)
	}
	if err := unix.Listen(fileDescriptor, unix.SOMAXCONN); err != nil {
		return nil, fmt.Errorf("Guest Product Release Manager control virtio-socket cannot listen on port %d: %w", port, err)
	}
	closeFileDescriptor = false
	return &listener{
		fileDescriptor: fileDescriptor,
		address:        address{cid: unix.VMADDR_CID_ANY, port: port},
	}, nil
}

type listener struct {
	fileDescriptor int
	address        address
	closeOnce      sync.Once
	closeError     error
}

func (value *listener) Accept() (net.Conn, error) {
	acceptedFileDescriptor, peerAddress, err := unix.Accept4(value.fileDescriptor, unix.SOCK_CLOEXEC)
	if err != nil {
		return nil, fmt.Errorf("Guest Product Release Manager control virtio-socket cannot accept: %w", err)
	}
	return &connection{
		fileDescriptor: acceptedFileDescriptor,
		localAddress:   value.address,
		remoteAddress:  addressFromSocketAddress(peerAddress),
	}, nil
}

func (value *listener) Close() error {
	value.closeOnce.Do(func() { value.closeError = unix.Close(value.fileDescriptor) })
	return value.closeError
}

func (value *listener) Addr() net.Addr { return value.address }

type connection struct {
	fileDescriptor int
	localAddress   address
	remoteAddress  address
	closeOnce      sync.Once
	closeError     error
}

func (value *connection) Read(buffer []byte) (int, error) {
	read, err := unix.Read(value.fileDescriptor, buffer)
	if err != nil {
		return read, fmt.Errorf("Guest Product Release Manager control virtio-socket cannot read: %w", err)
	}
	return read, nil
}

func (value *connection) Write(buffer []byte) (int, error) {
	written := 0
	for written < len(buffer) {
		count, err := unix.Write(value.fileDescriptor, buffer[written:])
		if err != nil {
			return written, fmt.Errorf("Guest Product Release Manager control virtio-socket cannot write: %w", err)
		}
		if count == 0 {
			return written, fmt.Errorf("Guest Product Release Manager control virtio-socket wrote zero bytes")
		}
		written += count
	}
	return written, nil
}

func (value *connection) Close() error {
	value.closeOnce.Do(func() { value.closeError = unix.Close(value.fileDescriptor) })
	return value.closeError
}

func (value *connection) LocalAddr() net.Addr  { return value.localAddress }
func (value *connection) RemoteAddr() net.Addr { return value.remoteAddress }

func (value *connection) SetDeadline(deadline time.Time) error {
	if err := value.SetReadDeadline(deadline); err != nil {
		return err
	}
	return value.SetWriteDeadline(deadline)
}

func (value *connection) SetReadDeadline(deadline time.Time) error {
	return value.setSocketDeadline(unix.SO_RCVTIMEO, deadline)
}

func (value *connection) SetWriteDeadline(deadline time.Time) error {
	return value.setSocketDeadline(unix.SO_SNDTIMEO, deadline)
}

func (value *connection) setSocketDeadline(option int, deadline time.Time) error {
	var timeout unix.Timeval
	if !deadline.IsZero() {
		remaining := time.Until(deadline)
		if remaining <= 0 {
			remaining = time.Microsecond
		}
		timeout = unix.NsecToTimeval(remaining.Nanoseconds())
	}
	if err := unix.SetsockoptTimeval(value.fileDescriptor, unix.SOL_SOCKET, option, &timeout); err != nil {
		return fmt.Errorf("Guest Product Release Manager control virtio-socket cannot set deadline: %w", err)
	}
	return nil
}

type address struct {
	cid  uint32
	port uint32
}

func (value address) Network() string { return "vsock" }
func (value address) String() string {
	return fmt.Sprintf("vsock://%d:%d", value.cid, value.port)
}

func addressFromSocketAddress(socketAddress unix.Sockaddr) address {
	virtioSocketAddress, isVirtioSocketAddress := socketAddress.(*unix.SockaddrVM)
	if !isVirtioSocketAddress {
		return address{}
	}
	return address{cid: virtioSocketAddress.CID, port: virtioSocketAddress.Port}
}
