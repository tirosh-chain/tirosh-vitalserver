package hypervprovider

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"strconv"
	"time"

	"github.com/tirosh/vitalserver-platform-agent/internal/provider"
)

const (
	vmNameEnvironment = "VITALSERVER_HYPERV_VM_NAME"
	startScript       = `$ErrorActionPreference = 'Stop'; $name = [Environment]::GetEnvironmentVariable('VITALSERVER_HYPERV_VM_NAME', 'Process'); $vm = Get-VM -Name $name -ErrorAction Stop; if ($vm.State -ne [Microsoft.HyperV.PowerShell.VMState]::Running) { Start-VM -VM $vm -ErrorAction Stop | Out-Null }`
	stopScript        = `$ErrorActionPreference = 'Stop'; $name = [Environment]::GetEnvironmentVariable('VITALSERVER_HYPERV_VM_NAME', 'Process'); $timeout = [int][Environment]::GetEnvironmentVariable('VITALSERVER_HYPERV_STOP_TIMEOUT_SECONDS', 'Process'); $vm = Get-VM -Name $name -ErrorAction Stop; if ($vm.State -ne [Microsoft.HyperV.PowerShell.VMState]::Off) { Stop-VM -VM $vm -Shutdown -ErrorAction Stop; $deadline = [DateTime]::UtcNow.AddSeconds($timeout); while ((Get-VM -Id $vm.Id -ErrorAction Stop).State -ne [Microsoft.HyperV.PowerShell.VMState]::Off) { if ([DateTime]::UtcNow -gt $deadline) { throw 'Hyper-V VM graceful shutdown timed out' }; Start-Sleep -Seconds 1 } }`
)

func NewRunner(config Config) provider.Runner {
	return provider.Runner{
		Name:            "Windows Hyper-V Runtime Provider",
		ReadyURL:        config.RuntimeReadyURL,
		EndpointAddress: config.RuntimeEndpointAddress,
		StartupTimeout:  config.StartupTimeout(),
		ShutdownTimeout: config.ShutdownTimeout(),
		Effect:          HyperVEffect{Config: config},
		Probe:           provider.HTTPReadinessProbe{Client: &http.Client{Timeout: 5 * time.Second}},
		Owner: provider.FileStateOwner{
			LifecyclePath: config.RuntimeProviderDocument,
			EndpointPath:  config.RuntimeEndpointDocument,
		},
		Now:          time.Now,
		PollInterval: time.Second,
		NewID:        provider.RandomID,
	}
}

type HyperVEffect struct {
	Config Config
}

func (effect HyperVEffect) Start(ctx context.Context) error {
	return effect.run(ctx, startScript)
}

func (effect HyperVEffect) Stop(ctx context.Context) error {
	return effect.run(ctx, stopScript)
}

func (effect HyperVEffect) run(ctx context.Context, script string) error {
	command := exec.CommandContext(
		ctx,
		effect.Config.PowerShellExecutable,
		"-NoLogo", "-NoProfile", "-NonInteractive", "-ExecutionPolicy", "Bypass", "-Command", script,
	)
	command.Env = append(
		os.Environ(),
		vmNameEnvironment+"="+effect.Config.VMName,
		"VITALSERVER_HYPERV_STOP_TIMEOUT_SECONDS="+strconv.Itoa(effect.Config.ShutdownTimeoutSeconds),
	)
	diagnostics := provider.NewTailBuffer(64 * 1024)
	command.Stdout = io.MultiWriter(os.Stdout, diagnostics)
	command.Stderr = io.MultiWriter(os.Stderr, diagnostics)
	if err := command.Run(); err != nil {
		return fmt.Errorf(
			"Hyper-V PowerShell effect failed outputTail=%q: %w",
			diagnostics.String(),
			err,
		)
	}
	return nil
}
