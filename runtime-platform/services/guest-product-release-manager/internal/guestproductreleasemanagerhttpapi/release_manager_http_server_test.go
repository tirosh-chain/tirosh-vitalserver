package guestproductreleasemanagerhttpapi

import (
	"bytes"
	"context"
	"encoding/json"
	"io"
	"mime/multipart"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-manager/internal/guestproductreleasemanagerdomain"
)

func TestReleaseUpdateHandlerStreamsTheDeclaredArchiveAfterTheCommand(t *testing.T) {
	t.Parallel()
	application := &recordingApplication{operation: succeededOperation()}
	handler, err := NewGuestProductReleaseManagerHTTPHandler(1024, application)
	if err != nil {
		t.Fatal(err)
	}
	body := bytes.NewBuffer(nil)
	writer := multipart.NewWriter(body)
	commandPart, err := writer.CreateFormField("command")
	if err != nil {
		t.Fatal(err)
	}
	if err := json.NewEncoder(commandPart).Encode(command()); err != nil {
		t.Fatal(err)
	}
	archivePart, err := writer.CreateFormFile("releaseArchive", "release.tar.gz")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := archivePart.Write([]byte("archive")); err != nil {
		t.Fatal(err)
	}
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	request := httptest.NewRequest(http.MethodPost, releaseUpdatesPath, body)
	request.Header.Set("Content-Type", writer.FormDataContentType())
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusOK {
		t.Fatalf("expected success, got %d: %s", response.Code, response.Body.String())
	}
	if application.appliedCommand.UpdateID != "update-01" || string(application.archive) != "archive" {
		t.Fatalf("application did not receive exact multipart values: %#v %q", application.appliedCommand, application.archive)
	}
}

func TestReleaseUpdateHandlerRejectsArchiveBeforeCommand(t *testing.T) {
	t.Parallel()
	handler, err := NewGuestProductReleaseManagerHTTPHandler(1024, &recordingApplication{operation: succeededOperation()})
	if err != nil {
		t.Fatal(err)
	}
	body := bytes.NewBuffer(nil)
	writer := multipart.NewWriter(body)
	archivePart, err := writer.CreateFormFile("releaseArchive", "release.tar.gz")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := archivePart.Write([]byte("archive")); err != nil {
		t.Fatal(err)
	}
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	request := httptest.NewRequest(http.MethodPost, releaseUpdatesPath, body)
	request.Header.Set("Content-Type", writer.FormDataContentType())
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusBadRequest {
		t.Fatalf("expected archive-order rejection, got %d: %s", response.Code, response.Body.String())
	}
}

func TestReleaseUpdateHandlerRejectsUndeclaredPartAfterArchive(t *testing.T) {
	t.Parallel()
	handler, err := NewGuestProductReleaseManagerHTTPHandler(1024, &recordingApplication{operation: succeededOperation()})
	if err != nil {
		t.Fatal(err)
	}
	body := bytes.NewBuffer(nil)
	writer := multipart.NewWriter(body)
	commandPart, err := writer.CreateFormField("command")
	if err != nil {
		t.Fatal(err)
	}
	if err := json.NewEncoder(commandPart).Encode(command()); err != nil {
		t.Fatal(err)
	}
	archivePart, err := writer.CreateFormFile("releaseArchive", "release.tar.gz")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := archivePart.Write([]byte("archive")); err != nil {
		t.Fatal(err)
	}
	trailingPart, err := writer.CreateFormField("unexpected")
	if err != nil {
		t.Fatal(err)
	}
	if _, err := trailingPart.Write([]byte("must-not-be-ignored")); err != nil {
		t.Fatal(err)
	}
	if err := writer.Close(); err != nil {
		t.Fatal(err)
	}
	request := httptest.NewRequest(http.MethodPost, releaseUpdatesPath, body)
	request.Header.Set("Content-Type", writer.FormDataContentType())
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, request)
	if response.Code != http.StatusInternalServerError {
		t.Fatalf("expected application-admission failure, got %d: %s", response.Code, response.Body.String())
	}
}

func TestReleaseUpdateHandlerReadsDurableOperation(t *testing.T) {
	t.Parallel()
	application := &recordingApplication{operation: succeededOperation(), found: true}
	handler, err := NewGuestProductReleaseManagerHTTPHandler(1024, application)
	if err != nil {
		t.Fatal(err)
	}
	response := httptest.NewRecorder()
	handler.ServeHTTP(response, httptest.NewRequest(http.MethodGet, releaseUpdatesPath+"/update-01", nil))
	if response.Code != http.StatusOK || application.readID != "update-01" {
		t.Fatalf("expected operation read, got %d id=%q", response.Code, application.readID)
	}
}

type recordingApplication struct {
	appliedCommand guestproductreleasemanagerdomain.GuestProductReleaseUpdateCommand
	archive        []byte
	operation      guestproductreleasemanagerdomain.GuestProductReleaseOperation
	found          bool
	readID         string
}

func (application *recordingApplication) ApplyReleaseUpdate(_ context.Context, command guestproductreleasemanagerdomain.GuestProductReleaseUpdateCommand, archive io.Reader) (guestproductreleasemanagerdomain.GuestProductReleaseOperation, error) {
	application.appliedCommand = command
	readArchive, err := io.ReadAll(archive)
	if err != nil {
		return guestproductreleasemanagerdomain.GuestProductReleaseOperation{}, err
	}
	application.archive = readArchive
	return application.operation, nil
}
func (application *recordingApplication) ReadReleaseOperation(_ context.Context, updateID string) (guestproductreleasemanagerdomain.GuestProductReleaseOperation, bool, error) {
	application.readID = updateID
	return application.operation, application.found, nil
}

func command() guestproductreleasemanagerdomain.GuestProductReleaseUpdateCommand {
	return guestproductreleasemanagerdomain.GuestProductReleaseUpdateCommand{
		SchemaVersion: "v1", UpdateID: "update-01", ExpectedActiveReleaseID: "release-01", RequestedAt: "2026-07-20T00:00:00Z",
		TargetRelease: guestproductreleasemanagerdomain.ReleaseTarget{ReleaseID: "release-02", ReleaseDirectory: "/opt/vitalserver/releases/release-02", Artifact: guestproductreleasemanagerdomain.ReleaseArtifact{SHA256: "0123456789012345678901234567890123456789012345678901234567890123", SizeBytes: 7, MediaType: "application/vnd.tirosh.vitalserver.guest-product-release+tar+gzip"}},
	}
}
func succeededOperation() guestproductreleasemanagerdomain.GuestProductReleaseOperation {
	value := command()
	return guestproductreleasemanagerdomain.GuestProductReleaseOperation{SchemaVersion: "v1", UpdateID: value.UpdateID, ExpectedActiveReleaseID: value.ExpectedActiveReleaseID, TargetRelease: value.TargetRelease, State: guestproductreleasemanagerdomain.OperationStateSucceeded, ActiveReleaseID: value.TargetRelease.ReleaseID, ObservedAt: "2026-07-20T00:01:00Z"}
}
