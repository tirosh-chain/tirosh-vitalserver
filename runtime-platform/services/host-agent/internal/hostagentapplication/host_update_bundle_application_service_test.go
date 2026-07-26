package hostagentapplication

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-agent/internal/hostagentdomain"
)

type updateBundleTestClock struct{}

func (updateBundleTestClock) Now() time.Time { return time.Date(2026, 7, 20, 0, 0, 0, 0, time.UTC) }

type updateBundleTestStore struct {
	receipt hostagentdomain.HostUpdateBundleImportReceipt
	bundle  hostagentdomain.HostUpdateBundleDeclaration
	err     error
}

func (store updateBundleTestStore) Import(context.Context, hostagentdomain.HostUpdateBundleImportCommand) (hostagentdomain.HostUpdateBundleImportReceipt, error) {
	return store.receipt, store.err
}

func (store updateBundleTestStore) Read(context.Context, string) (hostagentdomain.HostUpdateBundleDeclaration, error) {
	return store.bundle, store.err
}

func TestUpdateBundleImportPreservesTypedInvalidAndUnavailableStoreOutcomes(t *testing.T) {
	command := hostagentdomain.HostUpdateBundleImportCommand{SchemaVersion: "v1", RequestID: "import-020", SourceDirectory: "/operator/release"}
	service := &HostUpdateBundleApplicationService{store: updateBundleTestStore{err: ErrHostUpdateBundleInvalid}, updates: &HostUpdateApplicationService{}, clock: updateBundleTestClock{}}
	_, rejection, failure := service.ImportHostUpdateBundleCommand(context.Background(), command)
	if rejection == nil || rejection.Issue.Code != "host-update-bundle-invalid" || failure != nil {
		t.Fatalf("invalid import rejection=%+v failure=%+v", rejection, failure)
	}
	service.store = updateBundleTestStore{err: errors.New("storage read failed")}
	_, rejection, failure = service.ImportHostUpdateBundleCommand(context.Background(), command)
	if rejection != nil || failure == nil || failure.AdmissionState != "unknown" || failure.Issue.Code != "host-update-bundle-store-unavailable" {
		t.Fatalf("unavailable import rejection=%+v failure=%+v", rejection, failure)
	}
}

func TestUpdateBundleReadDoesNotConvertMissingOrInvalidIntoAvailable(t *testing.T) {
	service := &HostUpdateBundleApplicationService{store: updateBundleTestStore{err: ErrHostUpdateBundleNotFound}, updates: &HostUpdateApplicationService{}, clock: updateBundleTestClock{}}
	missing := service.ReadHostUpdateBundle(context.Background(), "release-bootstrap-020")
	if missing.State != "missing" || missing.Issue == nil || missing.Issue.Code != "host-update-bundle-missing" {
		t.Fatalf("missing read=%+v", missing)
	}
	service.store = updateBundleTestStore{err: ErrHostUpdateBundleInvalid}
	invalid := service.ReadHostUpdateBundle(context.Background(), "release-bootstrap-020")
	if invalid.State != "invalid" || invalid.Issue == nil || invalid.Issue.Code != "host-update-bundle-invalid" {
		t.Fatalf("invalid read=%+v", invalid)
	}
}
