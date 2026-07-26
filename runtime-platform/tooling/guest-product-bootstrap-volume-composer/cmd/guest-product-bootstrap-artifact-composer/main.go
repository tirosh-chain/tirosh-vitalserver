// guest-product-bootstrap-artifact-composer is the selected C35 release
// builder. It composes a Guest-owned bootstrap volume instead of editing the
// Linux root filesystem from the Host.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-bootstrap-volume-composer/internal/guestproductbootstrapartifactcompositionapplication"
)

func main() {
	compilationCommandPath := flag.String("guest-artifact-compilation-command", "", "required absolute C35 GuestArtifactCompilationCommand path")
	inputRoot := flag.String("input-root", "", "required absolute C35 input root")
	outputDirectory := flag.String("output-directory", "", "required absolute empty C35 compiler output directory")
	flag.Parse()
	if *compilationCommandPath == "" || *inputRoot == "" || *outputDirectory == "" {
		fmt.Fprintln(os.Stderr, "guest product bootstrap artifact composer requires --guest-artifact-compilation-command, --input-root, and --output-directory")
		os.Exit(2)
	}
	result, err := guestproductbootstrapartifactcompositionapplication.ExecuteGuestProductBootstrapArtifactComposition(
		guestproductbootstrapartifactcompositionapplication.GuestProductBootstrapArtifactCompositionExecution{
			GuestArtifactCompilationCommandPath: *compilationCommandPath,
			InputRoot:                           *inputRoot,
			OutputDirectory:                     *outputDirectory,
		},
	)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	if err := json.NewEncoder(os.Stdout).Encode(result); err != nil {
		fmt.Fprintln(os.Stderr, "guest product bootstrap artifact composer could not write result:", err)
		os.Exit(1)
	}
}
