package hostagentdomain

// HostUpdateBundleImportCommand asks the Host to copy one explicit release
// bundle directory into its update-bundle store.  sourceDirectory is a
// Host-local path selected through an OS-authorized interface; it is never a
// browser URL or a path interpreted by the Guest.
type HostUpdateBundleImportCommand struct {
	SchemaVersion   string `json:"schemaVersion"`
	RequestID       string `json:"requestId"`
	SourceDirectory string `json:"sourceDirectory"`
}

// HostUpdateBundleApplyCommand deliberately refers only to a bundle already
// owned by the Host store.  The Host reads the immutable C25 declaration from
// that store before it constructs the existing C27 HostUpdateCommand.
type HostUpdateBundleApplyCommand struct {
	SchemaVersion                string `json:"schemaVersion"`
	RequestID                    string `json:"requestId"`
	InstallationID               string `json:"installationId"`
	ExpectedInstallationRevision int    `json:"expectedInstallationRevision"`
	BundleReferenceID            string `json:"bundleReferenceId"`
}

// HostUpdateBundleDeclaration is the Host-owned, imported view of one C25
// release bundle.  Its State is deliberately "declared": importing bytes is
// not a claim that C25 trust verification or an update has succeeded.  C27's
// staged bootstrapper remains the trust-verification boundary.
type HostUpdateBundleDeclaration struct {
	SchemaVersion     string                  `json:"schemaVersion"`
	ID                string                  `json:"id"`
	State             string                  `json:"state"`
	BootstrapEnvelope UpdateBootstrapEnvelope `json:"bootstrapEnvelope"`
}

// HostUpdateBundleImportReceipt is a Host filesystem outcome.  `imported`
// means a complete new immutable directory was atomically published;
// `already-imported` means the exact same immutable bytes were already owned
// by the store.  Neither outcome verifies the signed envelope.
type HostUpdateBundleImportReceipt struct {
	SchemaVersion     string                      `json:"schemaVersion"`
	State             string                      `json:"state"`
	RequestID         string                      `json:"requestId"`
	ObservedAt        string                      `json:"observedAt"`
	Bundle            HostUpdateBundleDeclaration `json:"bundle"`
	SourceFingerprint string                      `json:"sourceFingerprint"`
}

func ValidateHostUpdateBundleImportCommand(command HostUpdateBundleImportCommand) *Issue {
	if command.SchemaVersion != SchemaVersion || !ValidIdentifier(command.RequestID) || command.SourceDirectory == "" {
		return &Issue{Code: "invalid-host-update-bundle-import-command", Message: "schemaVersion, requestId, and sourceDirectory are required"}
	}
	return nil
}

func ValidateHostUpdateBundleApplyCommand(command HostUpdateBundleApplyCommand) *Issue {
	if command.SchemaVersion != SchemaVersion || !ValidIdentifier(command.RequestID) || !ValidIdentifier(command.InstallationID) || command.ExpectedInstallationRevision < 1 || !ValidIdentifier(command.BundleReferenceID) {
		return &Issue{Code: "invalid-host-update-bundle-apply-command", Message: "Host update bundle apply command identity and expected installation revision are required"}
	}
	return nil
}

func ValidateHostUpdateBundleDeclaration(bundle HostUpdateBundleDeclaration) *Issue {
	if bundle.SchemaVersion != SchemaVersion || !ValidIdentifier(bundle.ID) || bundle.State != "declared" {
		return &Issue{Code: "host-update-bundle-declaration-invalid", Message: "bundle identity, schemaVersion, and declared state are required"}
	}
	if issue := ValidateUpdateBootstrapEnvelope(bundle.BootstrapEnvelope); issue != nil {
		return &Issue{Code: "host-update-bundle-declaration-invalid", Message: "bundle bootstrap envelope is invalid: " + issue.Code}
	}
	if bundle.ID != bundle.BootstrapEnvelope.ID {
		return &Issue{Code: "host-update-bundle-declaration-invalid", Message: "bundle id must equal its bootstrap envelope id"}
	}
	return nil
}

func ValidateHostUpdateBundleImportReceipt(receipt HostUpdateBundleImportReceipt) *Issue {
	if receipt.SchemaVersion != SchemaVersion || (receipt.State != "imported" && receipt.State != "already-imported") || !ValidIdentifier(receipt.RequestID) || receipt.ObservedAt == "" || receipt.SourceFingerprint == "" {
		return &Issue{Code: "host-update-bundle-import-receipt-invalid", Message: "import receipt identity, state, observedAt, and source fingerprint are required"}
	}
	return ValidateHostUpdateBundleDeclaration(receipt.Bundle)
}
