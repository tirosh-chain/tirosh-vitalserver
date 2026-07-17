//go:build linux

// Package guestpublicservicevirtiobridge adapts one C37-declared public Guest
// service route from AF_VSOCK to its explicit Guest-loopback TCP target. It
// does not own route selection, HTTP interpretation, service readiness, or
// upstream delivery state.
package guestpublicservicevirtiobridge

import (
	"context"
	"fmt"
	"io"
	"net"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/adapters/guestvirtiotransport"
)

// GuestPublicServiceVirtioSocketBridgeConfiguration is one complete C37 public route transport declaration after
// the process owner has decoded and validated desired input.
type GuestPublicServiceVirtioSocketBridgeConfiguration struct {
	RouteID          string
	VirtioSocketPort uint32
	TargetTCPAddress string
}

// Serve accepts C32-connected Host traffic until the supplied context ends.
// A TCP dial failure is isolated to one accepted client connection; it is not
// transformed into a process readiness or upstream success state.
func RunGuestPublicServiceVirtioSocketBridge(context context.Context, configuration GuestPublicServiceVirtioSocketBridgeConfiguration) error {
	listener, err := guestvirtiotransport.ListenGuestVirtioSocket(configuration.VirtioSocketPort)
	if err != nil {
		return fmt.Errorf("Guest public service route %s virtio-socket listener cannot start: %w", configuration.RouteID, err)
	}
	defer listener.Close()
	acceptedConnections := make(chan net.Conn, 1)
	acceptFailures := make(chan error, 1)
	go acceptGuestPublicServiceConnections(context, listener, acceptedConnections, acceptFailures)
	for {
		select {
		case <-context.Done():
			return nil
		case acceptFailure := <-acceptFailures:
			if context.Err() != nil {
				return nil
			}
			return fmt.Errorf("Guest public service route %s virtio-socket listener failed: %w", configuration.RouteID, acceptFailure)
		case acceptedConnection := <-acceptedConnections:
			go forwardGuestPublicServiceConnection(acceptedConnection, configuration.TargetTCPAddress)
		}
	}
}

func acceptGuestPublicServiceConnections(context context.Context, listener net.Listener, acceptedConnections chan<- net.Conn, acceptFailures chan<- error) {
	for {
		connection, err := listener.Accept()
		if err != nil {
			select {
			case acceptFailures <- err:
			default:
			}
			return
		}
		select {
		case <-context.Done():
			_ = connection.Close()
			return
		case acceptedConnections <- connection:
		}
	}
}

func forwardGuestPublicServiceConnection(hostConnection net.Conn, targetTCPAddress string) {
	defer hostConnection.Close()
	targetConnection, err := (&net.Dialer{Timeout: 5 * time.Second}).Dial("tcp", targetTCPAddress)
	if err != nil {
		return
	}
	defer targetConnection.Close()

	copyCompleted := make(chan struct{}, 2)
	copyBytes := func(destination net.Conn, source net.Conn) {
		_, _ = io.Copy(destination, source)
		closeWrite(destination)
		copyCompleted <- struct{}{}
	}
	go copyBytes(targetConnection, hostConnection)
	go copyBytes(hostConnection, targetConnection)
	<-copyCompleted
	// Closing both connection resources unblocks the opposite direction even
	// when an HTTP peer retained its half of the stream for keep-alive.
	_ = hostConnection.Close()
	_ = targetConnection.Close()
	<-copyCompleted
}

func closeWrite(connection net.Conn) {
	if tcpConnection, isTCPConnection := connection.(*net.TCPConn); isTCPConnection {
		_ = tcpConnection.CloseWrite()
	}
}
