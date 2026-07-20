package windowshostactivehostrelease

import (
	"context"
	"testing"
)

type commandRunnerFake struct{ result CommandResult }

func (fake commandRunnerFake) RunWindowsHostActiveReleaseCommand(_ context.Context, _ string, _ ...string) (CommandResult, error) {
	return fake.result, nil
}

func TestNewCurrentReleaseReaderRequiresExplicitFsutilContract(t *testing.T) {
	if _, err := NewCurrentReleaseReaderWithCommandRunner("", commandRunnerFake{}); err == nil {
		t.Fatal("expected missing fsutil path to be rejected")
	}
	reader, err := NewCurrentReleaseReaderWithCommandRunner("fsutil.exe", commandRunnerFake{result: CommandResult{Stdout: "Reparse Tag Value : 0xa0000003"}})
	if err != nil || reader == nil {
		t.Fatalf("reader=%v err=%v", reader, err)
	}
}
