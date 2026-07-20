// guest-bundled-upstream-image-set-archive-composer produces one immutable
// C64 image-set archive from explicit, local release-process inputs.
package main

import (
	"encoding/json"
	"flag"
	"fmt"
	"os"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-bundled-upstream-image-set-archive-composer/internal/guestbundledupstreamimagesetarchivecomposition"
)

func main() {
	compositionPath := flag.String("composition", "", "required absolute image-set archive composition JSON path")
	outputArchive := flag.String("output-archive", "", "required new absolute C64 tar+gzip archive path")
	flag.Parse()
	if flag.NArg() != 0 || *compositionPath == "" || *outputArchive == "" {
		fmt.Fprintln(os.Stderr, "usage: guest-bundled-upstream-image-set-archive-composer --composition <path> --output-archive <new-path>")
		os.Exit(2)
	}
	archive, err := guestbundledupstreamimagesetarchivecomposition.ComposeGuestBundledUpstreamImageSetArchive(guestbundledupstreamimagesetarchivecomposition.ComposeGuestBundledUpstreamImageSetArchiveRequest{
		CompositionPath:   *compositionPath,
		OutputArchivePath: *outputArchive,
	})
	if err != nil {
		fmt.Fprintf(os.Stderr, "compose Guest bundled Upstream image-set archive: %v\n", err)
		os.Exit(1)
	}
	if err := json.NewEncoder(os.Stdout).Encode(archive); err != nil {
		fmt.Fprintf(os.Stderr, "write Guest bundled Upstream image-set archive identity: %v\n", err)
		os.Exit(1)
	}
}
