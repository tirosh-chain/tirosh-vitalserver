// Package guestproductprocesssupervisorapplication orchestrates Guest Product process lifecycle effects.
package guestproductprocesssupervisorapplication

import (
	"context"
	"fmt"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-process-supervisor/internal/guestproductprocesssupervisordomain"
)

// GuestProductProcessLauncher is the sole process effect port. Its adapter
// starts an already planned invocation; it does not read deployment input or
// decide the required-process exit policy.
type GuestProductProcessLauncher interface {
	StartGuestProductProcess(invocation guestproductprocesssupervisordomain.GuestProductProcessInvocation) (GuestProductProcessLifecycleHandle, error)
}

// GuestProductProcessLifecycleHandle represents one started child process.
// Waiting and termination are separate effects because a child exit is an
// observed fact, not a supervisor policy decision.
type GuestProductProcessLifecycleHandle interface {
	WaitForGuestProductProcessExit() <-chan error
	TerminateGuestProductProcess() error
}

// RequiredGuestProductProcessExitedError records the exact required process
// whose observed exit ended the whole Guest product deployment.
type RequiredGuestProductProcessExitedError struct {
	DeploymentID string
	ProcessName  string
	Cause        error
}

func (failure RequiredGuestProductProcessExitedError) Error() string {
	if failure.Cause == nil {
		return fmt.Sprintf("Guest Product deployment %s stopped because required process %s exited", failure.DeploymentID, failure.ProcessName)
	}
	return fmt.Sprintf("Guest Product deployment %s stopped because required process %s exited: %v", failure.DeploymentID, failure.ProcessName, failure.Cause)
}

// GuestProductProcessStartError keeps process startup failure separate from a
// later process exit. The caller can distinguish an unavailable executable
// from an already-running process that later failed.
type GuestProductProcessStartError struct {
	DeploymentID string
	ProcessName  string
	Cause        error
}

// GuestProductProcessTerminationError preserves the distinct case where the
// supervisor observed an exit but could not apply the declared sibling stop
// effect. It never reports a fully stopped product in that case.
type GuestProductProcessTerminationError struct {
	DeploymentID string
	ProcessName  string
	Cause        error
}

func (failure GuestProductProcessTerminationError) Error() string {
	return fmt.Sprintf("Guest Product deployment %s could not terminate required process %s: %v", failure.DeploymentID, failure.ProcessName, failure.Cause)
}

func (failure GuestProductProcessStartError) Error() string {
	return fmt.Sprintf("Guest Product deployment %s could not start required process %s: %v", failure.DeploymentID, failure.ProcessName, failure.Cause)
}

// RunGuestProductProcessDeployment starts exactly the planned required
// processes. A required child exit or startup failure terminates the other
// child. Cancellation is an explicit supervisor shutdown, not child failure.
func RunGuestProductProcessDeployment(
	supervisionContext context.Context,
	deploymentConfiguration guestproductprocesssupervisordomain.GuestProductProcessDeploymentConfiguration,
	vitalServerTopologyDeployment guestproductprocesssupervisordomain.GuestProductVitalServerTopologyDeployment,
	externalVitalServerDeliveryConfiguration *guestproductprocesssupervisordomain.ExternalVitalServerDeliveryConfiguration,
	processLauncher GuestProductProcessLauncher,
) error {
	if processLauncher == nil {
		return fmt.Errorf("Guest Product process launcher is required")
	}
	resolution, err := guestproductprocesssupervisordomain.ResolveRecorderGatewayVitalServerDelivery(
		deploymentConfiguration.RecorderGateway,
		vitalServerTopologyDeployment,
		externalVitalServerDeliveryConfiguration,
	)
	if err != nil {
		return err
	}
	invocations, err := guestproductprocesssupervisordomain.PlanGuestProductProcessInvocations(deploymentConfiguration, resolution)
	if err != nil {
		return err
	}
	started := make([]startedGuestProductProcess, 0, len(invocations))
	for _, invocation := range invocations {
		process, startErr := processLauncher.StartGuestProductProcess(invocation)
		if startErr != nil {
			if terminationErr := terminateAndWaitForStartedGuestProductProcesses(started); terminationErr != nil {
				return GuestProductProcessTerminationError{DeploymentID: deploymentConfiguration.DeploymentID, ProcessName: terminationErr.processName, Cause: terminationErr.err}
			}
			return GuestProductProcessStartError{DeploymentID: deploymentConfiguration.DeploymentID, ProcessName: invocation.ProcessName, Cause: startErr}
		}
		if process == nil {
			if terminationErr := terminateAndWaitForStartedGuestProductProcesses(started); terminationErr != nil {
				return GuestProductProcessTerminationError{DeploymentID: deploymentConfiguration.DeploymentID, ProcessName: terminationErr.processName, Cause: terminationErr.err}
			}
			return GuestProductProcessStartError{DeploymentID: deploymentConfiguration.DeploymentID, ProcessName: invocation.ProcessName, Cause: fmt.Errorf("process launcher returned no managed process")}
		}
		started = append(started, startedGuestProductProcess{invocation: invocation, process: process})
	}

	exits := make(chan observedGuestProductProcessExit, len(started))
	for _, startedProcess := range started {
		go func(value startedGuestProductProcess) {
			exits <- observedGuestProductProcessExit{processName: value.invocation.ProcessName, err: <-value.process.WaitForGuestProductProcessExit()}
		}(startedProcess)
	}
	select {
	case <-supervisionContext.Done():
		if terminationErr := terminateAndWaitForAllObservedGuestProductProcesses(started, exits); terminationErr != nil {
			return GuestProductProcessTerminationError{DeploymentID: deploymentConfiguration.DeploymentID, ProcessName: terminationErr.processName, Cause: terminationErr.err}
		}
		return nil
	case exit := <-exits:
		if terminationErr := terminateAndWaitForOtherGuestProductProcess(started, exits, exit.processName); terminationErr != nil {
			return GuestProductProcessTerminationError{DeploymentID: deploymentConfiguration.DeploymentID, ProcessName: terminationErr.processName, Cause: terminationErr.err}
		}
		return RequiredGuestProductProcessExitedError{DeploymentID: deploymentConfiguration.DeploymentID, ProcessName: exit.processName, Cause: exit.err}
	}
}

type startedGuestProductProcess struct {
	invocation guestproductprocesssupervisordomain.GuestProductProcessInvocation
	process    GuestProductProcessLifecycleHandle
}

type observedGuestProductProcessExit struct {
	processName string
	err         error
}

type guestProductProcessTerminationFailure struct {
	processName string
	err         error
}

func terminateAndWaitForStartedGuestProductProcesses(processes []startedGuestProductProcess) *guestProductProcessTerminationFailure {
	for _, process := range processes {
		if err := process.process.TerminateGuestProductProcess(); err != nil {
			return &guestProductProcessTerminationFailure{processName: process.invocation.ProcessName, err: err}
		}
	}
	for _, process := range processes {
		<-process.process.WaitForGuestProductProcessExit()
	}
	return nil
}

func terminateAndWaitForOtherGuestProductProcess(processes []startedGuestProductProcess, exits <-chan observedGuestProductProcessExit, exemptProcessName string) *guestProductProcessTerminationFailure {
	otherProcessCount := 0
	for _, process := range processes {
		if process.invocation.ProcessName != exemptProcessName {
			otherProcessCount++
			if err := process.process.TerminateGuestProductProcess(); err != nil {
				return &guestProductProcessTerminationFailure{processName: process.invocation.ProcessName, err: err}
			}
		}
	}
	for count := 0; count < otherProcessCount; count++ {
		<-exits
	}
	return nil
}

func terminateAndWaitForAllObservedGuestProductProcesses(processes []startedGuestProductProcess, exits <-chan observedGuestProductProcessExit) *guestProductProcessTerminationFailure {
	for _, process := range processes {
		if err := process.process.TerminateGuestProductProcess(); err != nil {
			return &guestProductProcessTerminationFailure{processName: process.invocation.ProcessName, err: err}
		}
	}
	for range processes {
		<-exits
	}
	return nil
}
