package guestruntimedomain

// VitalServerIndexedLibraryCredentialMaterial is the private C51 document
// accepted only by the Guest-local secret-material boundary. Its UserID and
// Password must never enter a Guest Runtime SQLite document, an Operation,
// telemetry, an ordinary log, or an HTTP response.
type VitalServerIndexedLibraryCredentialMaterial struct {
	SchemaVersion       string                                       `json:"schemaVersion"`
	CredentialReference VitalServerIndexedLibraryCredentialReference `json:"credentialReference"`
	UserID              string                                       `json:"userId"`
	Password            string                                       `json:"password"`
}

// VitalServerIndexedLibraryCredentialReference identifies C51 material
// without containing it. C46 owns the expected reference; this type lets the
// secret owner prove only identity and availability to an operator.
type VitalServerIndexedLibraryCredentialReference struct {
	Kind string `json:"kind"`
	ID   string `json:"id"`
}

// VitalServerIndexedLibraryCredentialMaterialAvailability is a non-secret
// read model. It deliberately has no UserID, Password, file path, byte count,
// digest, or filesystem error because those would expose private material or
// turn an infrastructure detail into a public contract.
type VitalServerIndexedLibraryCredentialMaterialAvailability struct {
	SchemaVersion       string                                        `json:"schemaVersion"`
	State               string                                        `json:"state"`
	ObservedAt          string                                        `json:"observedAt"`
	CredentialReference *VitalServerIndexedLibraryCredentialReference `json:"credentialReference,omitempty"`
	Issue               *Issue                                        `json:"issue,omitempty"`
}

// VitalServerIndexedLibraryCredentialMaterialProvisioningOutcome is the
// immediate result of an OS-local private write. It is not a durable receipt:
// C51 itself must not be copied to state or response history.
type VitalServerIndexedLibraryCredentialMaterialProvisioningOutcome struct {
	SchemaVersion       string                                        `json:"schemaVersion"`
	State               string                                        `json:"state"`
	ObservedAt          string                                        `json:"observedAt"`
	CredentialReference *VitalServerIndexedLibraryCredentialReference `json:"credentialReference,omitempty"`
	Issue               *Issue                                        `json:"issue,omitempty"`
}

func ValidateVitalServerIndexedLibraryCredentialMaterial(material VitalServerIndexedLibraryCredentialMaterial) *Issue {
	if material.SchemaVersion != SchemaVersion {
		return &Issue{Code: "unsupported-schema-version", Message: "schemaVersion must be v1"}
	}
	if !ValidIdentifier(material.CredentialReference.Kind) || !ValidIdentifier(material.CredentialReference.ID) {
		return &Issue{Code: "invalid-credential-reference", Message: "credentialReference kind and id must be valid v1 identifiers"}
	}
	if material.UserID == "" || len(material.UserID) > 1024 || material.Password == "" || len(material.Password) > 4096 {
		return &Issue{Code: "invalid-credential-material", Message: "credential material requires bounded non-empty userId and password"}
	}
	return nil
}

func SameVitalServerIndexedLibraryCredentialReference(left VitalServerIndexedLibraryCredentialReference, right VitalServerIndexedLibraryCredentialReference) bool {
	return left.Kind == right.Kind && left.ID == right.ID
}

// OptionalVitalServerIndexedLibraryCredentialReference keeps an invalid or
// unavailable secret identity out of a non-secret response. Consumers can
// distinguish that absence from a valid C46 identity through the explicit
// outcome state and issue; they must never receive an empty reference that
// could be mistaken for a real secret owner.
func OptionalVitalServerIndexedLibraryCredentialReference(reference VitalServerIndexedLibraryCredentialReference) *VitalServerIndexedLibraryCredentialReference {
	if !ValidIdentifier(reference.Kind) || !ValidIdentifier(reference.ID) {
		return nil
	}
	return &reference
}
