//go:build linux

// Package guestvirtiotransport owns the Linux AF_VSOCK socket adaptation used
// by Guest-local transport adapters. It knows no HTTP route, Guest Runtime
// readiness, Recorder state, or Host lifecycle policy.
package guestvirtiotransport

import (
	"fmt"
	"net"
	"sync"
	"time"

	"golang.org/x/sys/unix"
)

// ListenGuestVirtioSocket creates one Linux AF_VSOCK stream listener. Callers
// own the domain name and meaning of the declared port.
func ListenGuestVirtioSocket(port uint32) (net.Listener, error) {
	if port == 0 || port > uint32(^uint16(0)) {
		return nil, fmt.Errorf("Guest virtio-socket port must be between 1 and 65535")
	}
	fileDescriptor, err := unix.Socket(unix.AF_VSOCK, unix.SOCK_STREAM|unix.SOCK_CLOEXEC, 0)
	if err != nil {
		return nil, fmt.Errorf("Guest virtio-socket cannot be created: %w", err)
	}
	closeFileDescriptor := true
	defer func() {
		if closeFileDescriptor {
			_ = unix.Close(fileDescriptor)
		}
	}()
	if err := unix.Bind(fileDescriptor, &unix.SockaddrVM{CID: unix.VMADDR_CID_ANY, Port: port}); err != nil {
		return nil, fmt.Errorf("Guest virtio-socket cannot bind port %d: %w", port, err)
	}
	if err := unix.Listen(fileDescriptor, unix.SOMAXCONN); err != nil {
		return nil, fmt.Errorf("Guest virtio-socket cannot listen on port %d: %w", port, err)
	}
	closeFileDescriptor = false
	return &guestVirtioSocketListener{
		fileDescriptor: fileDescriptor,
		address:        guestVirtioSocketAddress{cid: unix.VMADDR_CID_ANY, port: port},
	}, nil
}

type guestVirtioSocketListener struct {
	fileDescriptor int
	address        guestVirtioSocketAddress
	closeOnce      sync.Once
	closeError     error
}

func (listener *guestVirtioSocketListener) Accept() (net.Conn, error) {
	acceptedFileDescriptor, peerAddress, err := unix.Accept4(listener.fileDescriptor, unix.SOCK_CLOEXEC)
	if err != nil {
		return nil, fmt.Errorf("Guest virtio-socket cannot accept: %w", err)
	}
	return &guestVirtioSocketConnection{
		fileDescriptor: acceptedFileDescriptor,
		localAddress:   listener.address,
		remoteAddress:  guestVirtioSocketAddressFromSocketAddress(peerAddress),
	}, nil
}

func (listener *guestVirtioSocketListener) Close() error {
	listener.closeOnce.Do(func() { listener.closeError = unix.Close(listener.fileDescriptor) })
	return listener.closeError
}

func (listener *guestVirtioSocketListener) Addr() net.Addr { return listener.address }

type guestVirtioSocketConnection struct {
	fileDescriptor int
	localAddress   guestVirtioSocketAddress
	remoteAddress  guestVirtioSocketAddress
	closeOnce      sync.Once
	closeError     error
}

func (connection *guestVirtioSocketConnection) Read(buffer []byte) (int, error) {
	read, err := unix.Read(connection.fileDescriptor, buffer)
	if err != nil {
		return read, fmt.Errorf("Guest virtio-socket cannot read: %w", err)
	}
	return read, nil
}

func (connection *guestVirtioSocketConnection) Write(buffer []byte) (int, error) {
	written := 0
	for written < len(buffer) {
		count, err := unix.Write(connection.fileDescriptor, buffer[written:])
		if err != nil {
			return written, fmt.Errorf("Guest virtio-socket cannot write: %w", err)
		}
		if count == 0 {
			return written, fmt.Errorf("Guest virtio-socket wrote zero bytes")
		}
		written += count
	}
	return written, nil
}

func (connection *guestVirtioSocketConnection) Close() error {
	connection.closeOnce.Do(func() { connection.closeError = unix.Close(connection.fileDescriptor) })
	return connection.closeError
}

func (connection *guestVirtioSocketConnection) LocalAddr() net.Addr  { return connection.localAddress }
func (connection *guestVirtioSocketConnection) RemoteAddr() net.Addr { return connection.remoteAddress }

func (connection *guestVirtioSocketConnection) SetDeadline(deadline time.Time) error {
	if err := connection.SetReadDeadline(deadline); err != nil {
		return err
	}
	return connection.SetWriteDeadline(deadline)
}

func (connection *guestVirtioSocketConnection) SetReadDeadline(deadline time.Time) error {
	return connection.setSocketDeadline(unix.SO_RCVTIMEO, deadline)
}

func (connection *guestVirtioSocketConnection) SetWriteDeadline(deadline time.Time) error {
	return connection.setSocketDeadline(unix.SO_SNDTIMEO, deadline)
}

func (connection *guestVirtioSocketConnection) setSocketDeadline(option int, deadline time.Time) error {
	var timeout unix.Timeval
	if !deadline.IsZero() {
		remaining := time.Until(deadline)
		if remaining <= 0 {
			remaining = time.Microsecond
		}
		timeout = unix.NsecToTimeval(remaining.Nanoseconds())
	}
	if err := unix.SetsockoptTimeval(connection.fileDescriptor, unix.SOL_SOCKET, option, &timeout); err != nil {
		return fmt.Errorf("Guest virtio-socket cannot set deadline: %w", err)
	}
	return nil
}

type guestVirtioSocketAddress struct {
	cid  uint32
	port uint32
}

func (address guestVirtioSocketAddress) Network() string { return "vsock" }
func (address guestVirtioSocketAddress) String() string {
	return fmt.Sprintf("vsock://%d:%d", address.cid, address.port)
}

func guestVirtioSocketAddressFromSocketAddress(address unix.Sockaddr) guestVirtioSocketAddress {
	virtioSocketAddress, isVirtioSocketAddress := address.(*unix.SockaddrVM)
	if !isVirtioSocketAddress {
		return guestVirtioSocketAddress{}
	}
	return guestVirtioSocketAddress{cid: virtioSocketAddress.CID, port: virtioSocketAddress.Port}
}
