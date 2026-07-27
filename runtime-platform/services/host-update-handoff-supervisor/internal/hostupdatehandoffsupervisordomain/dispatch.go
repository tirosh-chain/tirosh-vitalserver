// Package hostupdatehandoffsupervisordomain owns the C31 dispatcher language.
// It deliberately understands C25 and C30 only far enough to locate the
// selected next updater; C26 and update settlement remain other owners.
package hostupdatehandoffsupervisordomain

import (
	"fmt"
	"regexp"
)

const SchemaVersion = "v1"

var (
	identifierPattern = regexp.MustCompile(`^[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$`)
	sha256Pattern     = regexp.MustCompile(`^[a-f0-9]{64}$`)
)

type HostUpdateHandoffSupervisorConfiguration struct {
	SchemaVersion                         string `json:"schemaVersion"`
	ID                                    string `json:"id"`
	StagingDirectory                      string `json:"stagingDirectory"`
	HandoffQueueDirectory                 string `json:"handoffQueueDirectory"`
	ExecutionEvidenceDirectory            string `json:"executionEvidenceDirectory"`
	LayerEffectReceiptDirectory           string `json:"layerEffectReceiptDirectory"`
	HostLocalAdministrationDescriptorPath string `json:"hostLocalAdministrationDescriptorPath"`
	LayerEffectTimeoutMilliseconds        int    `json:"layerEffectTimeoutMilliseconds"`
	CompletionTimeoutMilliseconds         int    `json:"completionTimeoutMilliseconds"`
	ServicePollIntervalMilliseconds       int    `json:"servicePollIntervalMilliseconds"`
}

// StagedUpdateHandoff is C31. The supervisor receives a specific durable
// queue entry; it must never discover invocation files by scanning staging.
type StagedUpdateHandoff struct {
	SchemaVersion          string `json:"schemaVersion"`
	UpdateID               string `json:"updateId"`
	InvocationRelativePath string `json:"invocationRelativePath"`
}

// StagedNextUpdaterDispatchInput is complete, verified adapter input for one
// next-updater invocation. The application does not inspect staged files.
type StagedNextUpdaterDispatchInput struct {
	UpdateID                       string
	InvocationRelativePath         string
	InvocationPath                 string
	ExpectedHandoffJournalRevision int
	NextUpdaterPath                string
	NextUpdaterSHA256              string
	ExecutionReportPath            string
	LayerEffectReceiptPath         string
	CompletionDescriptorPath       string
	LayerEffectTimeoutMilliseconds int
	CompletionTimeoutMilliseconds  int
	ExecutionMode                  string
}

type StagedNextUpdaterCompletionSubmission struct {
	CompletionCommandSHA256 string
}

type HostUpdateInterruptionObservation struct {
	InstallationID        string
	InstallationRevision  int
	UpdateID              string
	JournalRevision       int
	InterruptionRequestID string
}

type HostUpdateInterruptionConfirmation struct {
	SchemaVersion                string            `json:"schemaVersion"`
	RequestID                    string            `json:"requestId"`
	UpdateID                     string            `json:"updateId"`
	InstallationID               string            `json:"installationId"`
	ExpectedInstallationRevision int               `json:"expectedInstallationRevision"`
	ExpectedJournalRevision      int               `json:"expectedJournalRevision"`
	InterruptionRequestID        string            `json:"interruptionRequestId"`
	TerminationEvidence          EvidenceReference `json:"terminationEvidence"`
	Outcome                      DispatchIssue     `json:"outcome"`
	ObservedAt                   string            `json:"observedAt"`
}

type DispatchIssue struct {
	Code       string `json:"code"`
	Message    string `json:"message,omitempty"`
	Retryable  *bool  `json:"retryable,omitempty"`
	Dependency string `json:"dependency"`
}

type HostUpdateHandoffDispatchReceipt struct {
	SchemaVersion           string            `json:"schemaVersion"`
	AttemptID               string            `json:"attemptId"`
	UpdateID                string            `json:"updateId,omitempty"`
	InvocationRelativePath  string            `json:"invocationRelativePath,omitempty"`
	NextUpdaterSHA256       string            `json:"nextUpdaterSha256,omitempty"`
	ExecutionMode           string            `json:"executionMode,omitempty"`
	State                   string            `json:"state"`
	StartedAt               string            `json:"startedAt"`
	FinishedAt              string            `json:"finishedAt"`
	Evidence                EvidenceReference `json:"evidence"`
	CompletionCommandSHA256 string            `json:"completionCommandSha256,omitempty"`
	Issue                   *DispatchIssue    `json:"issue,omitempty"`
}

type EvidenceReference struct {
	Kind string `json:"kind"`
	ID   string `json:"id"`
}

// DispatchFailure is an explicit adapter result. It distinguishes unavailable
// Host-owned inputs from a failed, invalid, or rejected dispatch without
// creating an update-success meaning from process diagnostics.
type DispatchFailure struct {
	State string
	Issue DispatchIssue
}

func (failure DispatchFailure) Error() string { return failure.Issue.Message }

func ValidateConfiguration(configuration HostUpdateHandoffSupervisorConfiguration) error {
	if configuration.SchemaVersion != SchemaVersion || !validIdentifier(configuration.ID) {
		return fmt.Errorf("C56 schemaVersion and id are invalid")
	}
	for _, path := range []string{configuration.StagingDirectory, configuration.HandoffQueueDirectory, configuration.ExecutionEvidenceDirectory, configuration.LayerEffectReceiptDirectory, configuration.HostLocalAdministrationDescriptorPath} {
		if path == "" {
			return fmt.Errorf("C56 Host-owned paths are required")
		}
	}
	if configuration.LayerEffectTimeoutMilliseconds < 1 || configuration.LayerEffectTimeoutMilliseconds > 86400000 || configuration.CompletionTimeoutMilliseconds < 1 || configuration.CompletionTimeoutMilliseconds > 120000 || configuration.ServicePollIntervalMilliseconds < 100 || configuration.ServicePollIntervalMilliseconds > 86400000 {
		return fmt.Errorf("C56 update timeouts are invalid")
	}
	return nil
}

func ValidateHandoff(handoff StagedUpdateHandoff) error {
	if handoff.SchemaVersion != SchemaVersion || !validIdentifier(handoff.UpdateID) || handoff.InvocationRelativePath == "" {
		return fmt.Errorf("C31 handoff identity is invalid")
	}
	return nil
}

func ValidateDispatchInput(input StagedNextUpdaterDispatchInput) error {
	if !validIdentifier(input.UpdateID) || input.InvocationRelativePath == "" || input.InvocationPath == "" || input.ExpectedHandoffJournalRevision < 1 || input.NextUpdaterPath == "" || !sha256Pattern.MatchString(input.NextUpdaterSHA256) || input.ExecutionReportPath == "" || input.LayerEffectReceiptPath == "" || input.CompletionDescriptorPath == "" || input.LayerEffectTimeoutMilliseconds < 1 || input.CompletionTimeoutMilliseconds < 1 || (input.ExecutionMode != "execute" && input.ExecutionMode != "complete") {
		return fmt.Errorf("verified next-updater dispatch input is invalid")
	}
	return nil
}

func ValidateCompletionSubmission(submission StagedNextUpdaterCompletionSubmission) error {
	if !sha256Pattern.MatchString(submission.CompletionCommandSHA256) {
		return fmt.Errorf("C27 completion command digest is invalid")
	}
	return nil
}

func ValidateHostUpdateInterruptionObservation(observation HostUpdateInterruptionObservation, updateID string) error {
	if !validIdentifier(observation.InstallationID) || observation.InstallationRevision < 1 || observation.UpdateID != updateID || !validIdentifier(observation.UpdateID) || observation.JournalRevision < 1 || !validIdentifier(observation.InterruptionRequestID) {
		return fmt.Errorf("Host update interruption observation does not identify the exact active update owner")
	}
	return nil
}

func NewHostUpdateInterruptionConfirmation(attemptID string, observation HostUpdateInterruptionObservation, observedAt string) (HostUpdateInterruptionConfirmation, error) {
	if !validIdentifier(attemptID) || observedAt == "" {
		return HostUpdateInterruptionConfirmation{}, fmt.Errorf("interruption confirmation attempt and time are required")
	}
	if err := ValidateHostUpdateInterruptionObservation(observation, observation.UpdateID); err != nil {
		return HostUpdateInterruptionConfirmation{}, err
	}
	requestID := "interruption-confirmation-" + attemptID
	if !validIdentifier(requestID) {
		return HostUpdateInterruptionConfirmation{}, fmt.Errorf("interruption confirmation request identifier is invalid")
	}
	return HostUpdateInterruptionConfirmation{
		SchemaVersion:                SchemaVersion,
		RequestID:                    requestID,
		UpdateID:                     observation.UpdateID,
		InstallationID:               observation.InstallationID,
		ExpectedInstallationRevision: observation.InstallationRevision,
		ExpectedJournalRevision:      observation.JournalRevision,
		InterruptionRequestID:        observation.InterruptionRequestID,
		TerminationEvidence:          EvidenceReference{Kind: "host-update-process-termination", ID: attemptID},
		Outcome:                      DispatchIssue{Code: "staged-next-updater-terminated", Message: "Host Update Handoff Supervisor cancelled and waited for the staged next-updater process", Dependency: "host-update-handoff-supervisor"},
		ObservedAt:                   observedAt,
	}, nil
}

func validIdentifier(value string) bool { return identifierPattern.MatchString(value) }
