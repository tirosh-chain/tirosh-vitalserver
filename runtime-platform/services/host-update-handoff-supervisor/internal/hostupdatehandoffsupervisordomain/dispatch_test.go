package hostupdatehandoffsupervisordomain

import "testing"

func TestValidateDispatchInputRejectsMissingSelectedUpdaterDigest(t *testing.T) {
	input := StagedNextUpdaterDispatchInput{UpdateID: "update-020", InvocationRelativePath: "updates/update-020/invocation.json", InvocationPath: "/staging/updates/update-020/invocation.json", ExpectedHandoffJournalRevision: 3, NextUpdaterPath: "/staging/updates/update-020/payload/host-updater", ExecutionReportPath: "/evidence/update-020/execution-report.json", LayerEffectReceiptPath: "/effects/update-020", CompletionDescriptorPath: "/control/host.json", LayerEffectTimeoutMilliseconds: 1000, CompletionTimeoutMilliseconds: 1000, ExecutionMode: "execute"}
	if err := ValidateDispatchInput(input); err == nil {
		t.Fatal("expected missing updater digest to be rejected")
	}
}

func TestValidateCompletionSubmissionRequiresDigest(t *testing.T) {
	if err := ValidateCompletionSubmission(StagedNextUpdaterCompletionSubmission{}); err == nil {
		t.Fatal("expected missing completion command digest to be rejected")
	}
}

func TestValidateConfigurationRequiresAnExplicitServicePollInterval(t *testing.T) {
	configuration := HostUpdateHandoffSupervisorConfiguration{
		SchemaVersion:                         "v1",
		ID:                                    "dispatcher",
		StagingDirectory:                      "/staging",
		HandoffQueueDirectory:                 "/staging/handoff-queue",
		ExecutionEvidenceDirectory:            "/evidence",
		LayerEffectReceiptDirectory:           "/effects",
		HostLocalAdministrationDescriptorPath: "/control/host.json",
		LayerEffectTimeoutMilliseconds:        1000,
		CompletionTimeoutMilliseconds:         1000,
	}
	if err := ValidateConfiguration(configuration); err == nil {
		t.Fatal("expected C56 without an explicit service poll interval to be rejected")
	}
	configuration.ServicePollIntervalMilliseconds = 100
	if err := ValidateConfiguration(configuration); err != nil {
		t.Fatalf("expected explicit C56 service poll interval to validate: %v", err)
	}
}
