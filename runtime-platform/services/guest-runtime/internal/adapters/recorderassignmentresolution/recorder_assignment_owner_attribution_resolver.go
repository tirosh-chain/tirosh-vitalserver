// Package recorderassignmentresolution provides explicitly selected Recorder
// assignment-owner adapters for Archive attribution.
package recorderassignmentresolution

import (
	"context"
	"fmt"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

const RecorderAssignmentOwnerPolicyKind = "recorder-assignment-owner"

type recorderAssignmentOwner interface {
	ResolveRecorderAssignment(
		context.Context,
		string,
		string,
	) (guestruntimedomain.RecorderAssignmentResolution, error)
}

type RecorderAssignmentOwnerAttributionResolver struct {
	owner recorderAssignmentOwner
}

func NewRecorderAssignmentOwnerAttributionResolver(
	owner recorderAssignmentOwner,
) (*RecorderAssignmentOwnerAttributionResolver, error) {
	if owner == nil {
		return nil, fmt.Errorf("Recorder assignment owner is required")
	}
	return &RecorderAssignmentOwnerAttributionResolver{owner: owner}, nil
}

func (resolver *RecorderAssignmentOwnerAttributionResolver) ResolveRecorderArtifactAttribution(
	ctx context.Context,
	source guestruntimedomain.RecorderVitalUploadSourceReceipt,
	artifactID string,
	resolvedAt string,
) (guestruntimedomain.RecorderAttributionResolutionInput, error) {
	if resolver == nil || resolver.owner == nil {
		return guestruntimedomain.RecorderAttributionResolutionInput{},
			fmt.Errorf("Recorder assignment owner resolver is not configured")
	}
	if err := guestruntimedomain.ValidateRecorderVitalUploadSourceReceipt(source); err != nil {
		return guestruntimedomain.RecorderAttributionResolutionInput{}, err
	}
	resolution, err := resolver.owner.ResolveRecorderAssignment(
		ctx,
		source.ReportedBedName,
		source.FinalizedAt,
	)
	if err != nil {
		return guestruntimedomain.RecorderAttributionResolutionInput{}, err
	}
	if err := guestruntimedomain.ValidateRecorderAssignmentResolution(resolution); err != nil {
		return guestruntimedomain.RecorderAttributionResolutionInput{},
			fmt.Errorf("validate Recorder assignment owner resolution: %w", err)
	}
	return guestruntimedomain.RecorderAttributionResolutionInput{
		ArtifactID:         artifactID,
		ReportedBedName:    &source.ReportedBedName,
		EvidenceObservedAt: source.FinalizedAt,
		AssignmentEvidenceReference: &guestruntimedomain.EvidenceReference{
			Kind: guestruntimedomain.RecorderAssignmentResolutionReferenceKind,
			ID:   resolution.ResolutionID,
		},
		CandidateRecorderIDs: resolution.CandidateRecorderIDs,
		PolicyVersion:        resolution.PolicyVersion,
		ResolvedAt:           resolvedAt,
	}, nil
}

var _ guestruntimeapplication.GuestRuntimeRecorderArtifactAttributionResolver = (*RecorderAssignmentOwnerAttributionResolver)(nil)
