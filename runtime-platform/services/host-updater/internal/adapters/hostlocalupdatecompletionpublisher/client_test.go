package hostlocalupdatecompletionpublisher

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-updater/internal/hostupdaterdomain"
)

func stagedProductUpdateCompletionCommand() hostupdaterdomain.StagedProductUpdateCompletionCommand {
	return hostupdaterdomain.StagedProductUpdateCompletionCommand{SchemaVersion: "v1", UpdateID: "update-001", ExpectedJournalRevision: 3, Report: hostupdaterdomain.StagedProductUpdateExecutionReport{SchemaVersion: "v1", UpdateID: "update-001", RequestID: "request-001"}}
}

func TestHostLocalStagedProductUpdateCompletionHTTPPublisherPublishesC27ToTheExactHostLocalRoute(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(response http.ResponseWriter, request *http.Request) {
		if request.Method != http.MethodPost || request.URL.Path != "/v1/platform/updates/update-001:complete" {
			t.Fatalf("request method=%s path=%s", request.Method, request.URL.Path)
		}
		var command hostupdaterdomain.StagedProductUpdateCompletionCommand
		if err := json.NewDecoder(request.Body).Decode(&command); err != nil || command.ExpectedJournalRevision != 3 {
			t.Fatalf("command=%+v err=%v", command, err)
		}
		response.WriteHeader(http.StatusAccepted)
	}))
	defer server.Close()
	publisher, err := NewHostLocalStagedProductUpdateCompletionHTTPPublisher(server.Client())
	if err != nil {
		t.Fatal(err)
	}
	if err := publisher.Publish(context.Background(), server.URL, stagedProductUpdateCompletionCommand()); err != nil {
		t.Fatal(err)
	}
}

func TestHostLocalStagedProductUpdateCompletionHTTPPublisherRejectsEndpointWithUnexpectedPath(t *testing.T) {
	publisher, err := NewHostLocalStagedProductUpdateCompletionHTTPPublisher(http.DefaultClient)
	if err != nil {
		t.Fatal(err)
	}
	if err := publisher.Publish(context.Background(), "http://127.0.0.1:18330/unexpected", stagedProductUpdateCompletionCommand()); err == nil {
		t.Fatal("expected endpoint path to be rejected")
	}
}
