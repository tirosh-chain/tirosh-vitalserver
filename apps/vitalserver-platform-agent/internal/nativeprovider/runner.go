package nativeprovider

import (
	"context"
	"fmt"
	"io"
	"net/http"
	"os"
	"os/exec"
	"time"

	"github.com/tirosh/vitalserver-platform-agent/internal/provider"
)

func NewRunner(config Config) provider.Runner {
	return provider.Runner{
		Name:            "Linux Native Runtime Provider",
		ReadyURL:        config.RuntimeReadyURL,
		EndpointAddress: config.RuntimeEndpointAddress,
		StartupTimeout:  config.StartupTimeout(),
		ShutdownTimeout: config.ShutdownTimeout(),
		Effect:          ComposeEffect{Config: config},
		Probe:           provider.HTTPReadinessProbe{Client: &http.Client{Timeout: config.ReadinessProbeTimeout()}},
		Owner: provider.FileStateOwner{
			LifecyclePath: config.RuntimeProviderDocument,
			EndpointPath:  config.RuntimeEndpointDocument,
		},
		Now:          time.Now,
		PollInterval: time.Second,
		NewID:        provider.RandomID,
	}
}

type ComposeEffect struct {
	Config Config
}

func (effect ComposeEffect) Start(ctx context.Context) error {
	return runCompose(ctx, effect.Config, "up", "--detach", "--remove-orphans")
}

func (effect ComposeEffect) Stop(ctx context.Context) error {
	return runCompose(ctx, effect.Config, "down", "--remove-orphans")
}

func runCompose(ctx context.Context, config Config, action ...string) error {
	arguments := composeArguments(config, action...)
	command := exec.CommandContext(ctx, config.ComposeExecutable, arguments...)
	command.Dir = config.ProjectDirectory
	diagnostics := provider.NewTailBuffer(64 * 1024)
	command.Stdout = io.MultiWriter(os.Stdout, diagnostics)
	command.Stderr = io.MultiWriter(os.Stderr, diagnostics)
	if err := command.Run(); err != nil {
		return fmt.Errorf(
			"executable=%s action=%s outputTail=%q: %w",
			config.ComposeExecutable,
			action[0],
			diagnostics.String(),
			err,
		)
	}
	return nil
}

func composeArguments(config Config, action ...string) []string {
	arguments := []string{
		"compose",
		"--env-file", config.ComposeEnvironmentFile,
		"--project-name", config.ComposeProjectName,
		"--file", config.ComposeFile,
		"--project-directory", config.ProjectDirectory,
	}
	arguments = append(arguments, action...)
	return arguments
}
