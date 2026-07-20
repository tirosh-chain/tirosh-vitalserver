// Package guestproductreleaseprocess contains the narrow C59 adapters for
// systemd restart and the explicitly configured Guest Product health URL.
package guestproductreleaseprocess

import (
	"context"
	"fmt"
	"net/http"
	"os/exec"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-manager/internal/guestproductreleasemanagerapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-manager/internal/guestproductreleasemanagerdomain"
)

type SystemctlManagedGuestProductService struct {
	configuration guestproductreleasemanagerdomain.ManagerConfiguration
}

func NewSystemctlManagedGuestProductService(configuration guestproductreleasemanagerdomain.ManagerConfiguration) (*SystemctlManagedGuestProductService, error) {
	if err := guestproductreleasemanagerdomain.ValidateManagerConfiguration(configuration); err != nil {
		return nil, err
	}
	return &SystemctlManagedGuestProductService{configuration: configuration}, nil
}

func (service *SystemctlManagedGuestProductService) RestartManagedGuestProduct(context context.Context) *guestproductreleasemanagerapplication.ReleaseManagementFailure {
	deadline, cancel := contextWithMilliseconds(context, service.configuration.RestartTimeoutMilliseconds)
	defer cancel()
	if err := exec.CommandContext(deadline, service.configuration.SystemctlExecutablePath, "restart", service.configuration.ManagedServiceUnitName).Run(); err != nil {
		state := guestproductreleasemanagerdomain.OperationStateFailed
		if deadline.Err() != nil {
			state = guestproductreleasemanagerdomain.OperationStateUnavailable
		}
		return failure(state, "managed-service-restart-failed", err, "systemd")
	}
	return nil
}

type HTTPGuestProductHealthProbe struct {
	configuration guestproductreleasemanagerdomain.ManagerConfiguration
	client        *http.Client
}

func NewHTTPGuestProductHealthProbe(configuration guestproductreleasemanagerdomain.ManagerConfiguration) (*HTTPGuestProductHealthProbe, error) {
	if err := guestproductreleasemanagerdomain.ValidateManagerConfiguration(configuration); err != nil {
		return nil, err
	}
	return &HTTPGuestProductHealthProbe{configuration: configuration, client: &http.Client{}}, nil
}

func (probe *HTTPGuestProductHealthProbe) WaitForGuestProductHealth(context context.Context) *guestproductreleasemanagerapplication.ReleaseManagementFailure {
	deadline, cancel := contextWithMilliseconds(context, probe.configuration.HealthCheckTimeoutMilliseconds)
	defer cancel()
	accepted := map[int]struct{}{}
	for _, status := range probe.configuration.HealthCheckAcceptedStatusCodes {
		accepted[status] = struct{}{}
	}
	var lastError error
	for {
		request, err := http.NewRequestWithContext(deadline, http.MethodGet, probe.configuration.HealthCheckURL, nil)
		if err != nil {
			return failure(guestproductreleasemanagerdomain.OperationStateFailed, "health-check-request-invalid", err, "guest-product")
		}
		response, requestErr := probe.client.Do(request)
		if requestErr == nil {
			response.Body.Close()
			if _, found := accepted[response.StatusCode]; found {
				return nil
			}
			lastError = fmt.Errorf("health check returned status %d", response.StatusCode)
		} else {
			lastError = requestErr
		}
		select {
		case <-deadline.Done():
			if lastError == nil {
				lastError = deadline.Err()
			}
			return failure(guestproductreleasemanagerdomain.OperationStateFailed, "managed-service-health-check-failed", lastError, "guest-product")
		case <-time.After(250 * time.Millisecond):
		}
	}
}

func contextWithMilliseconds(parent context.Context, milliseconds int) (context.Context, context.CancelFunc) {
	return context.WithTimeout(parent, time.Duration(milliseconds)*time.Millisecond)
}
func failure(state string, code string, err error, dependency string) *guestproductreleasemanagerapplication.ReleaseManagementFailure {
	return &guestproductreleasemanagerapplication.ReleaseManagementFailure{State: state, Issue: guestproductreleasemanagerdomain.Issue{Code: code, Message: err.Error(), Dependency: dependency}}
}

var _ guestproductreleasemanagerapplication.ManagedGuestProductService = (*SystemctlManagedGuestProductService)(nil)
var _ guestproductreleasemanagerapplication.GuestProductHealthProbe = (*HTTPGuestProductHealthProbe)(nil)
