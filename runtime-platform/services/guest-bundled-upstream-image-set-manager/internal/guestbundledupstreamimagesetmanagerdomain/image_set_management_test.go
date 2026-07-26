package guestbundledupstreamimagesetmanagerdomain

import "testing"

func TestImageSetActivationRequiresTheDeclaredTransitionOrder(t *testing.T) {
	operation := NewImageSetOperation(command(), "2026-07-20T00:00:00Z")
	var err error
	if operation, err = MarkImageSetStaged(operation, "2026-07-20T00:00:01Z"); err != nil { t.Fatal(err) }
	if operation, err = BeginImageLoad(operation, "2026-07-20T00:00:02Z"); err != nil { t.Fatal(err) }
	if operation, err = BeginContainerStart(operation, "2026-07-20T00:00:03Z"); err != nil { t.Fatal(err) }
	if operation, err = CompleteImageSetActivation(operation, "2026-07-20T00:00:04Z"); err != nil { t.Fatal(err) }
	if operation.State != OperationStateSucceeded || operation.ActiveImageSet == nil || operation.ActiveImageSet.ImageSetID != "bundled-upstream-030" { t.Fatalf("operation=%+v", operation) }
	if err := ValidateImageSetOperation(configuration(), operation); err != nil { t.Fatal(err) }
}

func TestUnprovisionedIsExplicitAndCannotHideAnImageSetID(t *testing.T) {
	if err := ValidateActiveImageSetSelection(ActiveImageSetSelection{State: SelectionUnprovisioned}); err != nil { t.Fatal(err) }
	if err := ValidateActiveImageSetSelection(ActiveImageSetSelection{State: SelectionUnprovisioned, ImageSetID: "hidden"}); err == nil { t.Fatal("unprovisioned image set with an id was accepted") }
}

func TestTerminalFailureCannotClaimAnActiveImageSet(t *testing.T) {
	operation := NewImageSetOperation(command(), "2026-07-20T00:00:00Z")
	failed, err := FailImageSetOperation(operation, "2026-07-20T00:00:01Z", OperationStateUnavailable, Issue{Code: "container-engine-unavailable", Message: "engine cannot be started", Dependency: "container-engine"})
	if err != nil { t.Fatal(err) }
	active := ActiveImageSetSelection{State: SelectionActive, ImageSetID: "bundled-upstream-030"}
	failed.ActiveImageSet = &active
	if err := ValidateImageSetOperation(configuration(), failed); err == nil { t.Fatal("failed operation with active claim was accepted") }
}

func configuration() ManagerConfiguration { return ManagerConfiguration{ManagerID: "bundled-upstream-image-set-manager", StateDirectory: "/var/lib/vitalserver/bundled-upstream-image-sets", StagingDirectory: "/var/lib/vitalserver/bundled-upstream-image-sets/staging", StateDirectoryMode: "0700", MaximumImageSetArtifactBytes: 1024 * 1024, ContainerEngineExecutablePath: "/usr/bin/docker", ContainerEngineComposeProjectID: "vitalserver-bundled-upstream"} }
func command() ImageSetUpdateCommand { return ImageSetUpdateCommand{SchemaVersion: SchemaVersion, UpdateID: "bundled-upstream-update-030", ExpectedActiveImageSet: ActiveImageSetSelection{State: SelectionActive, ImageSetID: "bundled-upstream-020"}, TargetImageSet: ImageSetTarget{ImageSetID: "bundled-upstream-030", Artifact: ImageSetArtifact{SHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", SizeBytes: 200, MediaType: ImageSetArchiveMediaType}}, RequestedAt: "2026-07-20T00:00:00Z"} }
