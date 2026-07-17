// release-composer creates one signed C25 release bundle from explicit input.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"

	"github.com/tirosh-chain/vitalserver-runtime-platform/release-composer/internal/releasebundle"
)

func main() {
	compositionPath := flag.String("composition", "", "required release bundle composition JSON path")
	payloadDirectory := flag.String("payload-directory", "", "required source payload directory")
	privateKeyPath := flag.String("private-key", "", "required base64 Ed25519 private key path")
	outputDirectory := flag.String("output-directory", "", "required empty bundle output parent directory")
	flag.Parse()
	result, err := releasebundle.ComposeReleaseBundle(releasebundle.ComposeReleaseBundleRequest{CompositionPath: *compositionPath, PayloadDirectory: *payloadDirectory, PrivateKeyPath: *privateKeyPath, OutputDirectory: *outputDirectory})
	if err != nil {
		fmt.Fprintf(os.Stderr, "compose release bundle: %v\n", err)
		os.Exit(1)
	}
	if err := json.NewEncoder(os.Stdout).Encode(result); err != nil {
		fmt.Fprintf(os.Stderr, "write release bundle result: %v\n", err)
		os.Exit(1)
	}
}
