//go:build linux

// Package guestbundledupstreamcontrolvirtiotransport owns C64's Guest
// AF_VSOCK listener. It transports HTTP bytes only; it has no Docker/state
// knowledge and never chooses a Host address.
package guestbundledupstreamcontrolvirtiotransport

import (
	"fmt"
	"net"
	"sync"
	"time"

	"golang.org/x/sys/unix"
)

func ListenImageSetManagerControlVirtioSocket(port uint32) (net.Listener, error) {
	if port == 0 || port > uint32(^uint16(0)) { return nil, fmt.Errorf("C64 control virtio-socket port must be between 1 and 65535") }
	fd, err := unix.Socket(unix.AF_VSOCK, unix.SOCK_STREAM|unix.SOCK_CLOEXEC, 0)
	if err != nil { return nil, fmt.Errorf("C64 control virtio-socket cannot be created: %w", err) }
	closeFD := true
	defer func(){ if closeFD { _ = unix.Close(fd) } }()
	if err := unix.Bind(fd, &unix.SockaddrVM{CID: unix.VMADDR_CID_ANY, Port: port}); err != nil { return nil, fmt.Errorf("C64 control virtio-socket cannot bind port %d: %w", port, err) }
	if err := unix.Listen(fd, unix.SOMAXCONN); err != nil { return nil, fmt.Errorf("C64 control virtio-socket cannot listen on port %d: %w", port, err) }
	closeFD = false
	return &listener{fd: fd, address: address{cid: unix.VMADDR_CID_ANY, port: port}}, nil
}

type listener struct { fd int; address address; closeOnce sync.Once; closeError error }
func (value *listener) Accept() (net.Conn, error) { accepted, peer, err := unix.Accept4(value.fd, unix.SOCK_CLOEXEC); if err != nil { return nil, fmt.Errorf("C64 control virtio-socket cannot accept: %w", err) }; return &connection{fd: accepted, local: value.address, remote: addressFromSocketAddress(peer)}, nil }
func (value *listener) Close() error { value.closeOnce.Do(func(){ value.closeError = unix.Close(value.fd) }); return value.closeError }
func (value *listener) Addr() net.Addr { return value.address }

type connection struct { fd int; local, remote address; closeOnce sync.Once; closeError error }
func (value *connection) Read(buffer []byte) (int, error) { count, err := unix.Read(value.fd, buffer); if err != nil { return count, fmt.Errorf("C64 control virtio-socket cannot read: %w", err) }; return count, nil }
func (value *connection) Write(buffer []byte) (int, error) { written := 0; for written < len(buffer) { count, err := unix.Write(value.fd, buffer[written:]); if err != nil { return written, fmt.Errorf("C64 control virtio-socket cannot write: %w", err) }; if count == 0 { return written, fmt.Errorf("C64 control virtio-socket wrote zero bytes") }; written += count }; return written, nil }
func (value *connection) Close() error { value.closeOnce.Do(func(){ value.closeError = unix.Close(value.fd) }); return value.closeError }
func (value *connection) LocalAddr() net.Addr { return value.local }
func (value *connection) RemoteAddr() net.Addr { return value.remote }
func (value *connection) SetDeadline(deadline time.Time) error { if err := value.SetReadDeadline(deadline); err != nil { return err }; return value.SetWriteDeadline(deadline) }
func (value *connection) SetReadDeadline(deadline time.Time) error { return value.setDeadline(unix.SO_RCVTIMEO, deadline) }
func (value *connection) SetWriteDeadline(deadline time.Time) error { return value.setDeadline(unix.SO_SNDTIMEO, deadline) }
func (value *connection) setDeadline(option int, deadline time.Time) error { var timeout unix.Timeval; if !deadline.IsZero() { remaining := time.Until(deadline); if remaining <= 0 { remaining = time.Microsecond }; timeout = unix.NsecToTimeval(remaining.Nanoseconds()) }; if err := unix.SetsockoptTimeval(value.fd, unix.SOL_SOCKET, option, &timeout); err != nil { return fmt.Errorf("C64 control virtio-socket cannot set deadline: %w", err) }; return nil }

type address struct { cid, port uint32 }
func (value address) Network() string { return "vsock" }
func (value address) String() string { return fmt.Sprintf("vsock://%d:%d", value.cid, value.port) }
func addressFromSocketAddress(socketAddress unix.Sockaddr) address { value, ok := socketAddress.(*unix.SockaddrVM); if !ok { return address{} }; return address{cid: value.CID, port: value.Port} }
