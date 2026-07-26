package main

import (
	"os"
	"runtime"

	"github.com/tirosh-chain/vitalserver-runtime-platform/os-provider-bridge/internal/nativeproviderbridge"
)

func main() {
	os.Exit(nativeproviderbridge.RunCLI(nativeproviderbridge.WindowsHyperVSCMProviderKind, os.Args[1:], os.Stdin, os.Stdout, os.Stderr, runtime.GOOS))
}
