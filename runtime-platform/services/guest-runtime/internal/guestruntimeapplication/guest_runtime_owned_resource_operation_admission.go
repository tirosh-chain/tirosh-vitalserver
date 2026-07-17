package guestruntimeapplication

import "github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"

// newGuestRuntimeOwnedResourceRunningOperation constructs the durable operation
// admitted before an application service observes or effects one of its own
// resources. It is intentionally aggregate-neutral: callers supply their
// bounded-context operation kind and owned resource identity. It neither reads
// nor changes an aggregate, persistence store, provider, or transport.
func newGuestRuntimeOwnedResourceRunningOperation(
	operationID string,
	operationKind string,
	requestID string,
	ownedResourceType string,
	ownedResourceID string,
	expectedResourceRevision int,
	admittedAt string,
	commandDigest string,
) (guestruntimedomain.Operation, error) {
	operation := guestruntimedomain.NewOperation(
		operationID,
		operationKind,
		requestID,
		ownedResourceType,
		ownedResourceID,
		expectedResourceRevision,
		admittedAt,
		commandDigest,
	)
	var transitionErr error
	operation, transitionErr = guestruntimedomain.TransitionOperation(operation, "accepted", admittedAt, nil)
	if transitionErr == nil {
		operation, transitionErr = guestruntimedomain.TransitionOperation(operation, "running", admittedAt, nil)
	}
	return operation, transitionErr
}
