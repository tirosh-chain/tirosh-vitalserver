// host-installation-manager is the one-shot macOS product-installation
// boundary. It may quiesce C48-declared Host services, but it never bootstraps
// Guest or Host product services itself.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/hostinstallationjournalfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/hostinstallationreceiptfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/hostproductinstallationmanifestfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/macoshostinstallationfootprint"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/macoshostproductreleaseactivation"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/macoshostproductservicequiescence"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

func main() {
	mode := flag.String("mode", "", "required installation mode: preflight, quiesce, or activate")
	manifestPath := flag.String("manifest", "", "required absolute C48 Host product installation manifest path")
	journalPath := flag.String("journal", "", "required absolute C50 installation journal path")
	receiptPath := flag.String("receipt", "", "required absolute C50 installation receipt path")
	requestID := flag.String("request-id", "", "required explicit C50 installation request identifier")
	installationID := flag.String("installation-id", "", "required explicit C48 Host installation identifier for preflight")
	releaseID := flag.String("release-id", "", "required explicit C48 release identifier expected by this transaction")
	pkgutilExecutablePath := flag.String("pkgutil", "/usr/sbin/pkgutil", "macOS pkgutil executable path")
	launchctlExecutablePath := flag.String("launchctl", "/bin/launchctl", "macOS launchctl executable path")
	flag.Parse()
	if *mode == "" || *manifestPath == "" || *journalPath == "" || *receiptPath == "" {
		fmt.Fprintln(os.Stderr, "mode, manifest, journal, and receipt are required")
		os.Exit(2)
	}
	workflow, err := newHostInstallationWorkflow(*pkgutilExecutablePath, *launchctlExecutablePath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "configure Host Installation Manager: %v\n", err)
		os.Exit(2)
	}
	var receipt hostinstallationmanagerdomain.HostInstallationReceipt
	switch *mode {
	case "preflight":
		if *requestID == "" || *installationID == "" || *releaseID == "" {
			fmt.Fprintln(os.Stderr, "preflight requires request-id, installation-id, and release-id")
			os.Exit(2)
		}
		request := hostinstallationmanagerdomain.HostInstallationRequest{
			SchemaVersion:     hostinstallationmanagerdomain.HostInstallationDocumentSchemaVersion,
			DocumentKind:      "host-installation-request",
			ID:                *requestID,
			InstallationID:    *installationID,
			ExpectedReleaseID: *releaseID,
			RequestedAt:       time.Now().UTC().Format(time.RFC3339),
		}
		request.Operation = hostinstallationmanagerdomain.HostInstallationOperationPreflight
		receipt, err = workflow.ExecuteHostInstallationPreflight(context.Background(), request, *manifestPath, *journalPath, *receiptPath)
	case "quiesce":
		receipt, err = workflow.ExecuteHostProductServiceQuiescence(context.Background(), *manifestPath, *journalPath, *receiptPath)
	case "activate":
		receipt, err = workflow.ExecuteHostProductReleaseActivation(context.Background(), *manifestPath, *journalPath, *receiptPath)
	default:
		fmt.Fprintln(os.Stderr, "installation mode is unsupported")
		os.Exit(2)
	}
	if err != nil {
		fmt.Fprintf(os.Stderr, "execute Host installation %s: %v\n", *mode, err)
		os.Exit(1)
	}
	if err := json.NewEncoder(os.Stdout).Encode(receipt); err != nil {
		fmt.Fprintf(os.Stderr, "encode Host installation receipt: %v\n", err)
		os.Exit(1)
	}
	if receipt.State == hostinstallationmanagerdomain.HostInstallationReceiptBlocked || receipt.State == hostinstallationmanagerdomain.HostInstallationReceiptFailed {
		os.Exit(1)
	}
}

func newHostInstallationWorkflow(pkgutilExecutablePath string, launchctlExecutablePath string) (*hostinstallationmanagerapplication.HostInstallationWorkflow, error) {
	footprintObserver, err := macoshostinstallationfootprint.NewMacOSHostInstallationFootprintObserver(pkgutilExecutablePath, launchctlExecutablePath)
	if err != nil {
		return nil, err
	}
	serviceQuiescer, err := macoshostproductservicequiescence.NewMacOSHostProductServiceQuiescer(launchctlExecutablePath)
	if err != nil {
		return nil, err
	}
	return hostinstallationmanagerapplication.NewHostInstallationWorkflow(
		hostproductinstallationmanifestfile.HostProductInstallationManifestFileReader{},
		footprintObserver,
		hostinstallationjournalfile.HostInstallationJournalFileStore{},
		hostinstallationreceiptfile.HostInstallationReceiptFileStore{},
		macoshostproductreleaseactivation.MacOSHostProductReleaseActivator{},
		serviceQuiescer,
		hostinstallationmanagerapplication.NewSystemHostInstallationClock(),
	)
}
