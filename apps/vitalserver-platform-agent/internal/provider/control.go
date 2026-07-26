package provider

import (
	"context"
	"fmt"
)

type Action string

const (
	ActionStart   Action = "start"
	ActionStop    Action = "stop"
	ActionRestart Action = "restart"
)

type EffectError struct {
	Kind    string
	Message string
}

func (err EffectError) Error() string { return err.Message }

func ValidateAction(action Action) error {
	switch action {
	case ActionStart, ActionStop, ActionRestart:
		return nil
	default:
		return fmt.Errorf("unsupported Runtime Provider action: %s", action)
	}
}

type Controller interface {
	RuntimeProviderControlAvailable() bool
	ControlRuntimeProvider(context.Context, Action) error
}
