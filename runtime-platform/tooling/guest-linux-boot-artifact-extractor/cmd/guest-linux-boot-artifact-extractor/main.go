// guest-linux-boot-artifact-extractor executes one explicit C42 declaration.
package main

import (
	"fmt"
	"os"

	extraction "github.com/tirosh-chain/vitalserver-runtime-platform/guest-linux-boot-artifact-extractor/internal/guestlinuxbootartifactextraction"
)

func main() {
	arguments := os.Args[1:]
	if len(arguments) != 4 || arguments[0] != "--guest-linux-boot-artifact-extraction-declaration" || arguments[2] != "--output-directory" {
		fmt.Fprintln(os.Stderr, "guest-linux-boot-artifact-extractor requires --guest-linux-boot-artifact-extraction-declaration <absolute-path> --output-directory <absent-absolute-path>")
		os.Exit(2)
	}
	_, err := extraction.ExecuteGuestLinuxBootArtifactExtraction(extraction.GuestLinuxBootArtifactExtractionExecution{
		GuestLinuxBootArtifactExtractionDeclarationPath: arguments[1],
		OutputDirectory: arguments[3],
	})
	if err != nil {
		fmt.Fprintln(os.Stderr, err.Error())
		os.Exit(1)
	}
}
