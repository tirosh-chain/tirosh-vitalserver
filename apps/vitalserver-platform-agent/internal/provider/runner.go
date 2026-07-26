package provider

import (
	"context"
	"errors"
	"fmt"
	"time"
)

type Effect interface {
	Start(context.Context) error
	Stop(context.Context) error
}

type ReadinessProbe interface {
	Read(context.Context, string) error
}

type StateOwner interface {
	WriteLifecycle(Document) error
	PublishEndpoint(string) error
	RemoveEndpoint() error
}

type Runner struct {
	Name            string
	ReadyURL        string
	EndpointAddress string
	StartupTimeout  time.Duration
	ShutdownTimeout time.Duration
	Effect          Effect
	Probe           ReadinessProbe
	Owner           StateOwner
	Now             func() time.Time
	PollInterval    time.Duration
	NewID           func() (string, error)
}

func (r Runner) Run(ctx context.Context) error {
	operationID, err := r.NewID()
	if err != nil {
		return fmt.Errorf("runtime provider operation ID generation failed: %w", err)
	}
	bootID, err := r.NewID()
	if err != nil {
		return fmt.Errorf("runtime provider boot ID generation failed: %w", err)
	}
	startedAt := r.Now()
	document := Starting(operationID, bootID, startedAt, startedAt.Add(r.StartupTimeout))
	document.Message = stringPointer(r.Name + " start requested")
	if err := r.Owner.WriteLifecycle(document); err != nil {
		return err
	}

	startupContext, cancelStartup := context.WithTimeout(ctx, r.StartupTimeout)
	defer cancelStartup()
	if err := r.Effect.Start(startupContext); err != nil {
		if errors.Is(err, context.Canceled) && ctx.Err() != nil {
			return r.stop(document)
		}
		return r.failAndClean(document, fmt.Sprintf("Runtime Provider start failed: %v", err))
	}
	document, err = Transition(document, EventRuntimeStarted, r.Now(), "Runtime Provider start effect completed; waiting for Runtime Controller")
	if err != nil {
		return err
	}
	if err := r.Owner.WriteLifecycle(document); err != nil {
		return r.cleanAfterOwnerFailure(err)
	}

	if err := r.waitForReadiness(startupContext); err != nil {
		if errors.Is(err, context.Canceled) && ctx.Err() != nil {
			return r.stop(document)
		}
		return r.failAndClean(document, fmt.Sprintf("Runtime Controller readiness failed url=%s reason=%v", r.ReadyURL, err))
	}
	if err := r.Owner.PublishEndpoint(r.EndpointAddress); err != nil {
		return r.failAndClean(document, fmt.Sprintf("Runtime endpoint publish failed: %v", err))
	}
	document, err = Transition(document, EventEndpointReady, r.Now(), "Runtime Controller endpoint is ready")
	if err != nil {
		return err
	}
	if err := r.Owner.WriteLifecycle(document); err != nil {
		return r.cleanAfterOwnerFailure(err)
	}

	<-ctx.Done()
	return r.stop(document)
}

func (r Runner) waitForReadiness(ctx context.Context) error {
	var lastProbeError error
	for {
		if err := r.Probe.Read(ctx, r.ReadyURL); err == nil {
			return nil
		} else {
			lastProbeError = err
		}
		timer := time.NewTimer(r.PollInterval)
		select {
		case <-ctx.Done():
			timer.Stop()
			return fmt.Errorf(
				"Runtime Controller readiness deadline reached lastProbeError=%v: %w",
				lastProbeError,
				ctx.Err(),
			)
		case <-timer.C:
		}
	}
}

func (r Runner) stop(document Document) error {
	stopping, transitionErr := Transition(document, EventStopRequested, r.Now(), r.Name+" stop requested")
	if transitionErr != nil {
		return transitionErr
	}
	if err := r.Owner.WriteLifecycle(stopping); err != nil {
		return err
	}
	if err := r.Owner.RemoveEndpoint(); err != nil {
		return r.fail(stopping, fmt.Sprintf("Runtime endpoint removal failed: %v", err))
	}
	shutdownContext, cancel := context.WithTimeout(context.Background(), r.ShutdownTimeout)
	defer cancel()
	if err := r.Effect.Stop(shutdownContext); err != nil {
		return r.fail(stopping, fmt.Sprintf("Runtime Provider stop failed: %v", err))
	}
	stopped, err := Transition(stopping, EventRuntimeStopped, r.Now(), "Runtime Provider stop effect completed")
	if err != nil {
		return err
	}
	return r.Owner.WriteLifecycle(stopped)
}

func (r Runner) failAndClean(document Document, message string) error {
	primary := r.fail(document, message)
	shutdownContext, cancel := context.WithTimeout(context.Background(), r.ShutdownTimeout)
	defer cancel()
	return errors.Join(
		primary,
		wrapCleanup("Runtime Provider cleanup", r.Effect.Stop(shutdownContext)),
		wrapCleanup("endpoint cleanup", r.Owner.RemoveEndpoint()),
	)
}

func (r Runner) cleanAfterOwnerFailure(ownerErr error) error {
	shutdownContext, cancel := context.WithTimeout(context.Background(), r.ShutdownTimeout)
	defer cancel()
	return errors.Join(
		ownerErr,
		wrapCleanup("Runtime Provider cleanup", r.Effect.Stop(shutdownContext)),
		wrapCleanup("endpoint cleanup", r.Owner.RemoveEndpoint()),
	)
}

func (r Runner) fail(document Document, message string) error {
	failed := Fail(document, r.Now(), "launch-failed", message)
	return errors.Join(errors.New(message), r.Owner.WriteLifecycle(failed))
}

func wrapCleanup(name string, err error) error {
	if err == nil {
		return nil
	}
	return fmt.Errorf("%s failed: %w", name, err)
}
