// guest-product-release-archive-composer creates one C59-compatible immutable
// Guest Product release archive from an explicitly selected release tree.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-release-archive-composer/internal/guestproductreleasearchivecomposition"
)

func main() {
	releaseSourceDirectory := flag.String("release-source-directory", "", "required absolute selected Guest Product release tree")
	outputArchive := flag.String("output-archive", "", "required new absolute C59 tar+gzip archive path")
	flag.Parse()
	if flag.NArg() != 0 || *releaseSourceDirectory == "" || *outputArchive == "" {
		fmt.Fprintln(os.Stderr, "usage: guest-product-release-archive-composer --release-source-directory <path> --output-archive <new-path>")
		os.Exit(2)
	}
	archive, err := guestproductreleasearchivecomposition.ComposeGuestProductReleaseArchive(guestproductreleasearchivecomposition.ComposeGuestProductReleaseArchiveRequest{
		ReleaseSourceDirectory: *releaseSourceDirectory,
		OutputArchivePath:      *outputArchive,
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "compose Guest Product release archive: %v\n", err)
		os.Exit(1)
	}
	if err := json.NewEncoder(os.Stdout).Encode(archive); err != nil {
		fmt.Fprintf(os.Stderr, "write Guest Product release archive result: %v\n", err)
		os.Exit(1)
	}
}
