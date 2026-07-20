// guest-product-release-update-composer creates the Guest Product-specific
// payload and C58 composition input that release-composer later signs as C25.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-update-composer/internal/guestproductreleaseupdatecomposition"
)

func main() {
	compositionPath := flag.String("composition", "", "required Guest Product release update composition JSON path")
	outputDirectory := flag.String("output-directory", "", "required new output directory for the prepared payload")
	flag.Parse()
	if flag.NArg() != 0 || *compositionPath == "" || *outputDirectory == "" {
		fmt.Fprintln(os.Stderr, "usage: guest-product-release-update-composer --composition <path> --output-directory <new-path>")
		os.Exit(2)
	}
	result, err := guestproductreleaseupdatecomposition.ComposeGuestProductReleaseUpdate(guestproductreleaseupdatecomposition.ComposeGuestProductReleaseUpdateRequest{
		CompositionPath: *compositionPath,
		OutputDirectory: *outputDirectory,
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "compose Guest Product release update: %v\n", err)
		os.Exit(1)
	}
	if err := json.NewEncoder(os.Stdout).Encode(result); err != nil {
		fmt.Fprintf(os.Stderr, "write Guest Product release update result: %v\n", err)
		os.Exit(1)
	}
}
