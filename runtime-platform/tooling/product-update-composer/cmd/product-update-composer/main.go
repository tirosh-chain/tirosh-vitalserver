// product-update-composer creates one complete Product update payload and the
// bootstrap composition input that release-composer later signs.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"

	"github.com/tirosh-chain/vitalserver-runtime-platform/product-update-composer/internal/productupdatecomposition"
)

func main() {
	compositionPath := flag.String("composition", "", "required Product update composition JSON path")
	outputDirectory := flag.String("output-directory", "", "required new output directory for the prepared payload")
	flag.Parse()
	if flag.NArg() != 0 || *compositionPath == "" || *outputDirectory == "" {
		fmt.Fprintln(os.Stderr, "usage: product-update-composer --composition <path> --output-directory <new-path>")
		os.Exit(2)
	}
	result, err := productupdatecomposition.ComposeProductUpdate(productupdatecomposition.ComposeProductUpdateRequest{
		CompositionPath: *compositionPath,
		OutputDirectory: *outputDirectory,
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "compose Product update: %v\n", err)
		os.Exit(1)
	}
	if err := json.NewEncoder(os.Stdout).Encode(result); err != nil {
		fmt.Fprintf(os.Stderr, "write Product update result: %v\n", err)
		os.Exit(1)
	}
}
