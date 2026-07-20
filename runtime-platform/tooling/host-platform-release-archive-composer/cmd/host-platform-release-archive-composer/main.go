// host-platform-release-archive-composer forms a deterministic C68 archive
// from one explicit release-process source selection.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-platform-release-archive-composer/internal/hostplatformreleasearchivecomposition"
)

func main() {
	compositionPath := flag.String("composition", "", "required absolute Host Platform release archive composition JSON path")
	outputArchive := flag.String("output-archive", "", "required new absolute C68 tar+gzip archive path")
	flag.Parse()
	if flag.NArg() != 0 || *compositionPath == "" || *outputArchive == "" {
		fmt.Fprintln(os.Stderr, "usage: host-platform-release-archive-composer --composition <path> --output-archive <new-path>")
		os.Exit(2)
	}
	archive, err := hostplatformreleasearchivecomposition.ComposeHostPlatformReleaseArchive(hostplatformreleasearchivecomposition.ComposeHostPlatformReleaseArchiveRequest{CompositionPath: *compositionPath, OutputArchivePath: *outputArchive})
	if err != nil {
		fmt.Fprintf(os.Stderr, "compose Host Platform C68 release archive: %v\n", err)
		os.Exit(1)
	}
	if err := json.NewEncoder(os.Stdout).Encode(archive); err != nil {
		fmt.Fprintf(os.Stderr, "write Host Platform C68 release archive identity: %v\n", err)
		os.Exit(1)
	}
}
