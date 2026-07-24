package guestruntimedomain_test

import (
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

func TestValidateLabReplaySourceAdmissionCommandKeepsLabSourceExplicit(t *testing.T) {
	command := labReplaySourceAdmissionCommand()
	if err := guestruntimedomain.ValidateLabReplaySourceAdmissionCommand(
		command,
		64<<20,
	); err != nil {
		t.Fatal(err)
	}
	command.MediaType = "application/octet-stream"
	if err := guestruntimedomain.ValidateLabReplaySourceAdmissionCommand(
		command,
		64<<20,
	); err == nil {
		t.Fatal("Lab replay source must use the explicit Vital media type")
	}
}

func TestValidateLabReplaySourceAdmissionCommandRejectsPathAsFileName(t *testing.T) {
	command := labReplaySourceAdmissionCommand()
	command.OriginalFileName = "../sample.vital"
	if err := guestruntimedomain.ValidateLabReplaySourceAdmissionCommand(
		command,
		64<<20,
	); err == nil {
		t.Fatal("originalFileName is a label, not a filesystem path")
	}
}

func labReplaySourceAdmissionCommand() guestruntimedomain.LabReplaySourceAdmissionCommand {
	return guestruntimedomain.LabReplaySourceAdmissionCommand{
		SchemaVersion:    guestruntimedomain.SchemaVersion,
		RequestID:        "lab-replay-source-request-1",
		SourceID:         "lab-replay-source-1",
		OriginalFileName: "sample.vital",
		MediaType:        guestruntimedomain.LabReplaySourceMediaType,
		ByteSize:         20,
		SHA256:           "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
	}
}
