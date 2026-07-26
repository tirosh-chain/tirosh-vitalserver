package guestruntimedomain

import (
	"crypto/sha256"
	"encoding/hex"
	"fmt"
	"slices"
	"strings"
	"time"
)

const (
	RecorderAssignmentAdministratorSourceKind = "administrator"
	RecorderAssignmentResolutionReferenceKind = "recorder-assignment-resolution"
	RecorderAssignmentPolicyVersion           = "time-bounded-assignment-v1"
	MaximumRecorderAssignmentCandidates       = 64
)

// RecorderAssignmentEvidence is one immutable assignment-owner fact. A bed
// name in an upload or observation is not this evidence.
type RecorderAssignmentEvidence struct {
	SchemaVersion   string            `json:"schemaVersion"`
	EvidenceID      string            `json:"evidenceId"`
	RecorderID      string            `json:"recorderId"`
	BedName         string            `json:"bedName"`
	EffectiveFrom   string            `json:"effectiveFrom"`
	EffectiveUntil  *string           `json:"effectiveUntil,omitempty"`
	ObservedAt      string            `json:"observedAt"`
	PersistedAt     string            `json:"persistedAt"`
	SourceKind      string            `json:"sourceKind"`
	SourceReference EvidenceReference `json:"sourceReference"`
}

type RecorderAssignmentEvidenceCommand struct {
	SchemaVersion   string            `json:"schemaVersion"`
	RequestID       string            `json:"requestId"`
	EvidenceID      string            `json:"evidenceId"`
	RecorderID      string            `json:"recorderId"`
	BedName         string            `json:"bedName"`
	EffectiveFrom   string            `json:"effectiveFrom"`
	EffectiveUntil  *string           `json:"effectiveUntil,omitempty"`
	ObservedAt      string            `json:"observedAt"`
	SourceKind      string            `json:"sourceKind"`
	SourceReference EvidenceReference `json:"sourceReference"`
}

type RecorderAssignmentEvidenceReceipt struct {
	SchemaVersion     string            `json:"schemaVersion"`
	RequestID         string            `json:"requestId"`
	Outcome           string            `json:"outcome"`
	EvidenceReference EvidenceReference `json:"evidenceReference"`
	PersistedAt       string            `json:"persistedAt"`
}

// RecorderAssignmentResolution is the assignment owner's immutable answer for
// one bed and one artifact time. Archive consumes the complete candidate set
// and this evidence reference; it does not query assignment tables itself.
type RecorderAssignmentResolution struct {
	SchemaVersion        string              `json:"schemaVersion"`
	ResolutionID         string              `json:"resolutionId"`
	BedName              string              `json:"bedName"`
	EffectiveAt          string              `json:"effectiveAt"`
	EvidenceReferences   []EvidenceReference `json:"evidenceReferences"`
	CandidateRecorderIDs []string            `json:"candidateRecorderIds"`
	PolicyVersion        string              `json:"policyVersion"`
	ResolvedAt           string              `json:"resolvedAt"`
}

func ValidateRecorderAssignmentEvidence(evidence RecorderAssignmentEvidence) error {
	if evidence.SchemaVersion != SchemaVersion ||
		!ValidIdentifier(evidence.EvidenceID) ||
		!ValidIdentifier(evidence.RecorderID) ||
		strings.TrimSpace(evidence.BedName) != evidence.BedName ||
		evidence.BedName == "" ||
		len(evidence.BedName) > 255 ||
		evidence.SourceKind != RecorderAssignmentAdministratorSourceKind ||
		!ValidIdentifier(evidence.SourceReference.Kind) ||
		!ValidIdentifier(evidence.SourceReference.ID) ||
		!validTimestamp(evidence.EffectiveFrom) ||
		!validTimestamp(evidence.ObservedAt) ||
		!validTimestamp(evidence.PersistedAt) {
		return fmt.Errorf("Recorder assignment evidence is incomplete or invalid")
	}
	effectiveFrom, _ := time.Parse(time.RFC3339Nano, evidence.EffectiveFrom)
	if evidence.EffectiveUntil != nil {
		if !validTimestamp(*evidence.EffectiveUntil) {
			return fmt.Errorf("Recorder assignment effectiveUntil is invalid")
		}
		effectiveUntil, _ := time.Parse(time.RFC3339Nano, *evidence.EffectiveUntil)
		if !effectiveUntil.After(effectiveFrom) {
			return fmt.Errorf("Recorder assignment effectiveUntil must be after effectiveFrom")
		}
	}
	return nil
}

func ValidateRecorderAssignmentEvidenceCommand(
	command RecorderAssignmentEvidenceCommand,
) error {
	if command.SchemaVersion != SchemaVersion ||
		!ValidIdentifier(command.RequestID) {
		return fmt.Errorf("Recorder assignment evidence command is incomplete or invalid")
	}
	return ValidateRecorderAssignmentEvidence(
		RecorderAssignmentEvidenceFromCommand(command, command.ObservedAt),
	)
}

func RecorderAssignmentEvidenceFromCommand(
	command RecorderAssignmentEvidenceCommand,
	persistedAt string,
) RecorderAssignmentEvidence {
	return RecorderAssignmentEvidence{
		SchemaVersion:   command.SchemaVersion,
		EvidenceID:      command.EvidenceID,
		RecorderID:      command.RecorderID,
		BedName:         command.BedName,
		EffectiveFrom:   command.EffectiveFrom,
		EffectiveUntil:  command.EffectiveUntil,
		ObservedAt:      command.ObservedAt,
		PersistedAt:     persistedAt,
		SourceKind:      command.SourceKind,
		SourceReference: command.SourceReference,
	}
}

func ResolveRecorderAssignment(
	bedName string,
	effectiveAt string,
	evidences []RecorderAssignmentEvidence,
	resolvedAt string,
) (RecorderAssignmentResolution, error) {
	if strings.TrimSpace(bedName) != bedName ||
		bedName == "" ||
		len(bedName) > 255 ||
		!validTimestamp(effectiveAt) ||
		!validTimestamp(resolvedAt) {
		return RecorderAssignmentResolution{},
			fmt.Errorf("Recorder assignment resolution input is incomplete or invalid")
	}
	if len(evidences) > MaximumRecorderAssignmentCandidates {
		return RecorderAssignmentResolution{},
			fmt.Errorf("Recorder assignment candidate limit exceeded")
	}
	targetTime, _ := time.Parse(time.RFC3339Nano, effectiveAt)
	evidenceReferences := make([]EvidenceReference, 0, len(evidences))
	recorderSet := map[string]struct{}{}
	for _, evidence := range evidences {
		if err := ValidateRecorderAssignmentEvidence(evidence); err != nil {
			return RecorderAssignmentResolution{}, err
		}
		if evidence.BedName != bedName {
			return RecorderAssignmentResolution{},
				fmt.Errorf("Recorder assignment evidence bed does not match resolution")
		}
		effectiveFrom, _ := time.Parse(time.RFC3339Nano, evidence.EffectiveFrom)
		if targetTime.Before(effectiveFrom) {
			return RecorderAssignmentResolution{},
				fmt.Errorf("Recorder assignment evidence is not effective at resolution time")
		}
		if evidence.EffectiveUntil != nil {
			effectiveUntil, _ := time.Parse(time.RFC3339Nano, *evidence.EffectiveUntil)
			if !targetTime.Before(effectiveUntil) {
				return RecorderAssignmentResolution{},
					fmt.Errorf("Recorder assignment evidence is not effective at resolution time")
			}
		}
		recorderSet[evidence.RecorderID] = struct{}{}
		evidenceReferences = append(evidenceReferences, EvidenceReference{
			Kind: "recorder-assignment-evidence",
			ID:   evidence.EvidenceID,
		})
	}
	candidateRecorderIDs := make([]string, 0, len(recorderSet))
	for recorderID := range recorderSet {
		candidateRecorderIDs = append(candidateRecorderIDs, recorderID)
	}
	slices.Sort(candidateRecorderIDs)
	slices.SortFunc(evidenceReferences, func(left, right EvidenceReference) int {
		return strings.Compare(left.ID, right.ID)
	})
	resolutionID := recorderAssignmentResolutionID(
		bedName,
		effectiveAt,
		evidenceReferences,
		candidateRecorderIDs,
	)
	return RecorderAssignmentResolution{
		SchemaVersion:        SchemaVersion,
		ResolutionID:         resolutionID,
		BedName:              bedName,
		EffectiveAt:          effectiveAt,
		EvidenceReferences:   evidenceReferences,
		CandidateRecorderIDs: candidateRecorderIDs,
		PolicyVersion:        RecorderAssignmentPolicyVersion,
		ResolvedAt:           resolvedAt,
	}, nil
}

func ValidateRecorderAssignmentResolution(
	resolution RecorderAssignmentResolution,
) error {
	if resolution.SchemaVersion != SchemaVersion ||
		!ValidIdentifier(resolution.ResolutionID) ||
		strings.TrimSpace(resolution.BedName) != resolution.BedName ||
		resolution.BedName == "" ||
		len(resolution.BedName) > 255 ||
		!validTimestamp(resolution.EffectiveAt) ||
		!validTimestamp(resolution.ResolvedAt) ||
		resolution.PolicyVersion != RecorderAssignmentPolicyVersion ||
		resolution.EvidenceReferences == nil ||
		resolution.CandidateRecorderIDs == nil ||
		len(resolution.EvidenceReferences) > MaximumRecorderAssignmentCandidates ||
		len(resolution.CandidateRecorderIDs) > MaximumRecorderAssignmentCandidates {
		return fmt.Errorf("Recorder assignment resolution is incomplete or invalid")
	}
	for index, reference := range resolution.EvidenceReferences {
		if reference.Kind != "recorder-assignment-evidence" ||
			!ValidIdentifier(reference.ID) {
			return fmt.Errorf("Recorder assignment resolution evidence is invalid")
		}
		if index > 0 &&
			strings.Compare(
				resolution.EvidenceReferences[index-1].ID,
				reference.ID,
			) >= 0 {
			return fmt.Errorf("Recorder assignment resolution evidence is not canonical")
		}
	}
	for index, recorderID := range resolution.CandidateRecorderIDs {
		if !ValidIdentifier(recorderID) {
			return fmt.Errorf("Recorder assignment resolution candidate is invalid")
		}
		if index > 0 &&
			strings.Compare(resolution.CandidateRecorderIDs[index-1], recorderID) >= 0 {
			return fmt.Errorf("Recorder assignment resolution candidates are not canonical")
		}
	}
	expectedResolutionID := recorderAssignmentResolutionID(
		resolution.BedName,
		resolution.EffectiveAt,
		resolution.EvidenceReferences,
		resolution.CandidateRecorderIDs,
	)
	if resolution.ResolutionID != expectedResolutionID {
		return fmt.Errorf("Recorder assignment resolution identity does not match its evidence")
	}
	return nil
}

func recorderAssignmentResolutionID(
	bedName string,
	effectiveAt string,
	evidenceReferences []EvidenceReference,
	candidateRecorderIDs []string,
) string {
	canonical := bedName + "\x00" + effectiveAt
	for _, reference := range evidenceReferences {
		canonical += "\x00" + reference.Kind + "\x00" + reference.ID
	}
	for _, recorderID := range candidateRecorderIDs {
		canonical += "\x00" + recorderID
	}
	digest := sha256.Sum256([]byte(canonical))
	return "assignment-resolution-" + hex.EncodeToString(digest[:16])
}
