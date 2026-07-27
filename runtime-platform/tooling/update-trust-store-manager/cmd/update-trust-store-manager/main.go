// update-trust-store-manager creates immutable public-key trust transitions
// for the Update Bootstrap Envelope. Private signing material is not accepted.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"

	"github.com/tirosh-chain/vitalserver-runtime-platform/update-trust-store-manager/internal/updatetrust"
)

func main() {
	action := flag.String("action", "", "required action: provision, rotate, or revoke")
	transitionID := flag.String("transition-id", "", "required transition identifier")
	sourceTrustStore := flag.String("source-trust-store", "", "required for rotate and revoke")
	expectedSourceSHA256 := flag.String("expected-source-sha256", "", "required for rotate and revoke")
	keyID := flag.String("key-id", "", "required public key identifier")
	publicKey := flag.String("public-key", "", "required base64 Ed25519 public key file for provision and rotate")
	transitionedAt := flag.String("transitioned-at", "", "required RFC3339 transition time")
	outputDirectory := flag.String("output-directory", "", "required new output directory")
	flag.Parse()

	result, err := updatetrust.Transition(updatetrust.TransitionRequest{
		Action:               *action,
		TransitionID:         *transitionID,
		SourceTrustStorePath: *sourceTrustStore,
		ExpectedSourceSHA256: *expectedSourceSHA256,
		KeyID:                *keyID,
		PublicKeyPath:        *publicKey,
		TransitionedAt:       *transitionedAt,
		OutputDirectory:      *outputDirectory,
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "update publisher trust transition failed: %v\n", err)
		os.Exit(1)
	}
	if err := json.NewEncoder(os.Stdout).Encode(result); err != nil {
		fmt.Fprintf(os.Stderr, "write update publisher trust transition result: %v\n", err)
		os.Exit(1)
	}
}
