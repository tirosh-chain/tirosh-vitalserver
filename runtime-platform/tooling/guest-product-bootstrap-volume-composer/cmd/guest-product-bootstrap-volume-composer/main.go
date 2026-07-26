// guest-product-bootstrap-volume-composer produces one explicitly declared
// NoCloud bootstrap volume. Its output is a Host release artifact; cloud-init
// in the Linux Guest owns applying the contents to its own root filesystem.
package main

import (
	"flag"
	"fmt"
	"os"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-bootstrap-volume-composer/internal/guestproductbootstrapvolumeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-product-bootstrap-volume-composer/internal/nocloudguestproductbootstrapvolumeadapter"
)

func main() {
	planPath := flag.String("guest-product-bootstrap-volume-composition-plan", "", "required absolute C40 GuestProductBootstrapVolumeCompositionPlan path")
	sourceRoot := flag.String("source-root", "", "required absolute C40 source root")
	outputVolume := flag.String("output-volume", "", "required absolute new NoCloud ISO9660 output path")
	flag.Parse()

	bootstrapID, err := guestproductbootstrapvolumeapplication.ExecuteGuestProductBootstrapVolumeComposition(
		guestproductbootstrapvolumeapplication.GuestProductBootstrapVolumeCompositionExecution{
			CompositionPlanPath: *planPath,
			SourceRoot:          *sourceRoot,
			OutputVolumePath:    *outputVolume,
		},
		nocloudguestproductbootstrapvolumeadapter.NewNoCloudGuestProductBootstrapVolumeAdapter(),
	)
	if err != nil {
		fmt.Fprintln(os.Stderr, "guest product bootstrap volume composition failed:", err)
		os.Exit(1)
	}
	fmt.Println("guest product bootstrap volume composed bootstrapId=" + bootstrapID)
}
