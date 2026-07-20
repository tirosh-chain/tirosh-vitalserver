//go:build !linux

package guestbundledupstreamcontrolvirtiotransport

import ("fmt"; "net")

func ListenImageSetManagerControlVirtioSocket(uint32) (net.Listener, error) { return nil, fmt.Errorf("C64 control virtio-socket is only available on Linux") }
