// host-installation-manager is the one-shot Host product-installation
// boundary. It composes native adapters only after it reads the explicit C48
// platform declaration; it never infers a release, Guest state, or package
// manager ownership from the host it happens to run on.
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
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/hostinstallationtransactionfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/hostplatformreleasearchiveadapter"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/hostplatformstagedreleaseoperationfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/hostplatformstagedreleasepublisher"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/hostproductinstallationmanifestfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/hostproductremovaljournalfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/hostproductremovalreceiptfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/linuxhostinstallationfootprint"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/linuxhostproductreleaseactivation"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/linuxhostproductremoval"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/macoshostinstallationfootprint"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/macoshostproductreleaseactivation"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/macoshostproductremoval"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/macoshostproductservicequiescence"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/macoshostproductservicereconciliation"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/systemdhostproductservicequiescence"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/systemdhostproductservicereconciliation"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/unixactivehostrelease"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/unixhoststagedreleaseactivation"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/windowshostactivehostrelease"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/windowshostinstallationfootprint"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/adapters/windowshostproductlifecycle"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostplatformstagedreleaseupdateapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostplatformstagedreleaseupdatedomain"
)

func main() {
	mode := flag.String("mode", "", "required installation mode: observe-footprint, preflight, quiesce, activate, finalize, recover, remove, complete-removal-after-package-manager, staged-update, or staged-update-recover")
	manifestPath := flag.String("manifest", "", "required absolute C48 Host product installation manifest path")
	journalPath := flag.String("journal", "", "required absolute C50 installation journal path")
	receiptPath := flag.String("receipt", "", "required absolute C50 installation receipt path")
	requestID := flag.String("request-id", "", "required explicit C50 installation request identifier")
	packageManagerOperation := flag.String("package-manager-operation", "", "optional explicit package-manager phase such as windows-msi-installing")
	installationID := flag.String("installation-id", "", "required explicit C48 Host installation identifier for preflight")
	releaseID := flag.String("release-id", "", "required explicit C48 release identifier expected by this transaction")
	dataDisposition := flag.String("data-disposition", "", "required C54 removal data disposition: preserve-mutable-data or purge-all-product-data")
	removalJournalPath := flag.String("removal-journal", "", "required absolute C54 removal journal path")
	removalReceiptPath := flag.String("removal-receipt", "", "required absolute C54 removal receipt path when preserving mutable data")
	packageManagerCompletionManagerPath := flag.String("package-manager-completion-manager", "", "required absolute C54 durable manager path for a dpkg/MSI post-removal completion")
	packageManagerCompletionManifestPath := flag.String("package-manager-completion-manifest", "", "required absolute C54 durable C48 manifest path for a dpkg/MSI post-removal completion")
	pkgutilExecutablePath := flag.String("pkgutil", "/usr/sbin/pkgutil", "macOS pkgutil executable path")
	launchctlExecutablePath := flag.String("launchctl", "/bin/launchctl", "macOS launchctl executable path")
	dpkgQueryExecutablePath := flag.String("dpkg-query", "/usr/bin/dpkg-query", "Linux dpkg-query executable path")
	systemctlExecutablePath := flag.String("systemctl", "/usr/bin/systemctl", "Linux systemctl executable path")
	registryExecutablePath := flag.String("reg", `C:\Windows\System32\reg.exe`, "Windows registry executable path")
	scExecutablePath := flag.String("sc", `C:\Windows\System32\sc.exe`, "Windows SCM executable path")
	fsutilExecutablePath := flag.String("fsutil", `C:\Windows\System32\fsutil.exe`, "Windows filesystem utility executable path")
	commandExecutablePath := flag.String("cmd", `C:\Windows\System32\cmd.exe`, "Windows command executable path")
	stagedOperationID := flag.String("operation-id", "", "required C68 Host Platform staged update operation identifier")
	stagedUpdateID := flag.String("update-id", "", "required C30 update identifier for C68 staged update")
	stagedOperation := flag.String("operation", "", "required C68 operation: apply or rollback")
	expectedActiveReleaseID := flag.String("expected-active-release-id", "", "required C68 active release compare-and-swap identity")
	targetReleaseID := flag.String("target-release-id", "", "required C68 target release identity")
	activeManifestPath := flag.String("active-manifest", "", "required C67 fixed current-slot C48 manifest path")
	artifactPath := flag.String("artifact-path", "", "required absolute verified C68 Host Platform archive path")
	artifactSHA256 := flag.String("artifact-sha256", "", "required C68 Host Platform archive SHA-256")
	recoveryID := flag.String("recovery-id", "", "required C68 explicit staged-update recovery identifier")
	recoveryAction := flag.String("recovery-action", "", "required C68 recovery action: reconcile-current-release")
	flag.Parse()
	if *mode == "staged-update" {
		executeStagedHostPlatformUpdate(*stagedOperationID, *stagedUpdateID, *stagedOperation, *expectedActiveReleaseID, *targetReleaseID, *activeManifestPath, *artifactPath, *artifactSHA256, *launchctlExecutablePath, *systemctlExecutablePath, *fsutilExecutablePath, *commandExecutablePath, *scExecutablePath)
		return
	}
	if *mode == "staged-update-recover" {
		executeStagedHostPlatformRecovery(*stagedOperationID, *recoveryID, *recoveryAction, *activeManifestPath, *launchctlExecutablePath, *systemctlExecutablePath, *fsutilExecutablePath, *commandExecutablePath, *scExecutablePath)
		return
	}
	if *mode == "" || *manifestPath == "" {
		fmt.Fprintln(os.Stderr, "mode and manifest are required")
		os.Exit(2)
	}
	if *mode != "observe-footprint" && (*journalPath == "" || *receiptPath == "") {
		fmt.Fprintln(os.Stderr, "mode, manifest, journal, and receipt are required")
		os.Exit(2)
	}
	manifest, err := hostproductinstallationmanifestfile.HostProductInstallationManifestFileReader{}.ReadHostProductInstallationManifest(context.Background(), *manifestPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "read C48 Host product installation manifest for composition: %v\n", err)
		os.Exit(2)
	}
	if *mode != "observe-footprint" {
		if err := validateDeclaredC50Paths(manifest, *journalPath, *receiptPath); err != nil {
			fmt.Fprintf(os.Stderr, "validate C48-declared C50 paths: %v\n", err)
			os.Exit(2)
		}
	}
	workflow, err := newHostInstallationWorkflowForPlatform(manifest.Platform, *pkgutilExecutablePath, *launchctlExecutablePath, *dpkgQueryExecutablePath, *systemctlExecutablePath, *registryExecutablePath, *scExecutablePath, *fsutilExecutablePath, *commandExecutablePath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "configure Host Installation Manager: %v\n", err)
		os.Exit(2)
	}
	var output any
	operationFailed := false
	var executionError error
	switch *mode {
	case "observe-footprint":
		footprint, err := workflow.ObserveDeclaredHostInstallationFootprint(context.Background(), *manifestPath)
		output = footprint
		executionError = err
	case "preflight":
		if *requestID == "" || *installationID == "" || *releaseID == "" {
			fmt.Fprintln(os.Stderr, "preflight requires request-id, installation-id, and release-id")
			os.Exit(2)
		}
		request := hostinstallationmanagerdomain.HostInstallationRequest{
			SchemaVersion:           hostinstallationmanagerdomain.HostInstallationDocumentSchemaVersion,
			DocumentKind:            "host-installation-request",
			ID:                      *requestID,
			InstallationID:          *installationID,
			ExpectedReleaseID:       *releaseID,
			PackageManagerOperation: *packageManagerOperation,
			RequestedAt:             time.Now().UTC().Format(time.RFC3339),
		}
		request.Operation = hostinstallationmanagerdomain.HostInstallationOperationPreflight
		receipt, err := workflow.ExecuteHostInstallationPreflight(context.Background(), request, *manifestPath, *journalPath, *receiptPath)
		output = receipt
		executionError = err
		operationFailed = receipt.State == hostinstallationmanagerdomain.HostInstallationReceiptBlocked || receipt.State == hostinstallationmanagerdomain.HostInstallationReceiptFailed
	case "quiesce":
		receipt, err := workflow.ExecuteHostProductServiceQuiescence(context.Background(), *manifestPath, *journalPath, *receiptPath)
		output = receipt
		executionError = err
		operationFailed = receipt.State == hostinstallationmanagerdomain.HostInstallationReceiptBlocked || receipt.State == hostinstallationmanagerdomain.HostInstallationReceiptFailed
	case "activate":
		receipt, err := workflow.ExecuteHostProductReleaseActivation(context.Background(), *manifestPath, *journalPath, *receiptPath)
		output = receipt
		executionError = err
		operationFailed = receipt.State == hostinstallationmanagerdomain.HostInstallationReceiptBlocked || receipt.State == hostinstallationmanagerdomain.HostInstallationReceiptFailed
	case "finalize":
		receipt, err := workflow.ExecuteHostProductServiceFinalization(context.Background(), *manifestPath, *journalPath, *receiptPath)
		output = receipt
		executionError = err
		operationFailed = receipt.State == hostinstallationmanagerdomain.HostInstallationReceiptBlocked || receipt.State == hostinstallationmanagerdomain.HostInstallationReceiptFailed
	case "recover":
		receipt, err := workflow.ExecuteHostInstallationRecovery(context.Background(), *manifestPath, *journalPath, *receiptPath)
		output = receipt
		executionError = err
		operationFailed = receipt.State == hostinstallationmanagerdomain.HostInstallationReceiptBlocked || receipt.State == hostinstallationmanagerdomain.HostInstallationReceiptFailed
	case "remove":
		if *requestID == "" || *installationID == "" || *releaseID == "" || *dataDisposition == "" || *removalJournalPath == "" {
			fmt.Fprintln(os.Stderr, "remove requires request-id, installation-id, release-id, data-disposition, and removal-journal")
			os.Exit(2)
		}
		if *dataDisposition == hostinstallationmanagerdomain.HostProductRemovalDataDispositionPreserveMutableData && *removalReceiptPath == "" {
			fmt.Fprintln(os.Stderr, "remove with preserve-mutable-data requires removal-receipt")
			os.Exit(2)
		}
		var packageManagerCompletionTransport *hostinstallationmanagerdomain.HostProductPackageManagerCompletionTransport
		if manifest.Platform != "macos" {
			if *packageManagerCompletionManagerPath == "" || *packageManagerCompletionManifestPath == "" {
				fmt.Fprintln(os.Stderr, "remove on a package-manager-owned platform requires package-manager-completion-manager and package-manager-completion-manifest")
				os.Exit(2)
			}
			packageManagerCompletionTransport = &hostinstallationmanagerdomain.HostProductPackageManagerCompletionTransport{ManagerPath: *packageManagerCompletionManagerPath, ManifestPath: *packageManagerCompletionManifestPath}
		}
		request := hostinstallationmanagerdomain.HostProductRemovalRequest{
			SchemaVersion:                     hostinstallationmanagerdomain.HostInstallationDocumentSchemaVersion,
			DocumentKind:                      "host-product-removal-request",
			ID:                                *requestID,
			InstallationID:                    *installationID,
			ExpectedReleaseID:                 *releaseID,
			DataDisposition:                   *dataDisposition,
			PackageManagerCompletionTransport: packageManagerCompletionTransport,
			RequestedAt:                       time.Now().UTC().Format(time.RFC3339),
		}
		receipt, err := workflow.ExecuteHostProductRemoval(context.Background(), request, *manifestPath, *journalPath, *receiptPath, *removalJournalPath, *removalReceiptPath)
		output = receipt
		executionError = err
		operationFailed = receipt.State == hostinstallationmanagerdomain.HostProductRemovalReceiptBlocked || receipt.State == hostinstallationmanagerdomain.HostProductRemovalReceiptFailed
	case "complete-removal-after-package-manager":
		if *removalJournalPath == "" || *removalReceiptPath == "" {
			fmt.Fprintln(os.Stderr, "complete-removal-after-package-manager requires removal-journal and removal-receipt")
			os.Exit(2)
		}
		receipt, err := workflow.CompleteHostProductRemovalAfterPackageManager(context.Background(), *manifestPath, *journalPath, *receiptPath, *removalJournalPath, *removalReceiptPath)
		output = receipt
		executionError = err
		operationFailed = receipt.State == hostinstallationmanagerdomain.HostProductRemovalReceiptBlocked || receipt.State == hostinstallationmanagerdomain.HostProductRemovalReceiptFailed
	default:
		fmt.Fprintln(os.Stderr, "installation mode is unsupported")
		os.Exit(2)
	}
	if executionError != nil {
		fmt.Fprintf(os.Stderr, "execute Host installation %s: %v\n", *mode, executionError)
		os.Exit(1)
	}
	if err := json.NewEncoder(os.Stdout).Encode(output); err != nil {
		fmt.Fprintf(os.Stderr, "encode Host installation receipt: %v\n", err)
		os.Exit(1)
	}
	if operationFailed {
		os.Exit(1)
	}
}

// validateDeclaredC50Paths keeps package scripts and operator input from
// redirecting a C50 workflow to arbitrary Host data. C48 owns the one store;
// the CLI is merely transport for those exact paths.
func validateDeclaredC50Paths(manifest hostinstallationmanagerdomain.HostProductInstallationManifest, journalPath, receiptPath string) error {
	expectedJournalPath, expectedReceiptPath, err := hostinstallationmanagerdomain.DeclaredHostInstallationTransactionPaths(manifest)
	if err != nil {
		return err
	}
	if journalPath != expectedJournalPath || receiptPath != expectedReceiptPath {
		return fmt.Errorf("journal and receipt paths must equal the C48-declared C50 paths")
	}
	return nil
}

func executeStagedHostPlatformUpdate(operationID, updateID, operation, expectedActiveReleaseID, targetReleaseID, activeManifestPath, artifactPath, artifactSHA256, launchctlExecutablePath, systemctlExecutablePath, fsutilExecutablePath, commandExecutablePath, scExecutablePath string) {
	if operationID == "" || updateID == "" || operation == "" || expectedActiveReleaseID == "" || targetReleaseID == "" || activeManifestPath == "" || artifactPath == "" || artifactSHA256 == "" {
		fmt.Fprintln(os.Stderr, "staged-update requires operation-id, update-id, operation, expected-active-release-id, target-release-id, active-manifest, artifact-path, and artifact-sha256")
		os.Exit(2)
	}
	platform, err := stagedHostPlatformForActiveManifestPath(activeManifestPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "staged-update active-manifest: %v\n", err)
		os.Exit(2)
	}
	info, err := os.Lstat(artifactPath)
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 || info.Size() < 1 {
		fmt.Fprintln(os.Stderr, "staged-update artifact is missing, non-regular, symbolic, or empty")
		os.Exit(2)
	}
	command := hostplatformstagedreleaseupdatedomain.StagedReleaseUpdateCommand{
		SchemaVersion: "v1", OperationID: operationID, UpdateID: updateID, Operation: operation,
		Transition:  hostplatformstagedreleaseupdatedomain.ReleaseTransition{ExpectedActiveReleaseID: expectedActiveReleaseID, TargetReleaseID: targetReleaseID},
		Artifact:    hostplatformstagedreleaseupdatedomain.ArchiveArtifact{SHA256: artifactSHA256, SizeBytes: info.Size(), MediaType: hostplatformstagedreleaseupdatedomain.HostPlatformReleaseArchiveMedia},
		RequestedAt: time.Now().UTC().Format(time.RFC3339),
	}
	workflow, err := newHostPlatformStagedReleaseWorkflow(platform, launchctlExecutablePath, systemctlExecutablePath, fsutilExecutablePath, commandExecutablePath, scExecutablePath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "configure C68 Host Installation Manager workflow: %v\n", err)
		os.Exit(2)
	}
	result, err := workflow.ExecuteHostPlatformStagedReleaseUpdate(context.Background(), command, activeManifestPath, artifactPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "execute C68 Host Platform staged update: %v\n", err)
		os.Exit(1)
	}
	if err := json.NewEncoder(os.Stdout).Encode(result); err != nil {
		fmt.Fprintf(os.Stderr, "encode C68 Host Platform operation: %v\n", err)
		os.Exit(1)
	}
	if result.State != hostplatformstagedreleaseupdatedomain.StateSucceeded {
		os.Exit(1)
	}
}

func executeStagedHostPlatformRecovery(operationID, recoveryID, recoveryAction, activeManifestPath, launchctlExecutablePath, systemctlExecutablePath, fsutilExecutablePath, commandExecutablePath, scExecutablePath string) {
	if operationID == "" || recoveryID == "" || recoveryAction == "" || activeManifestPath == "" {
		fmt.Fprintln(os.Stderr, "staged-update-recover requires operation-id, recovery-id, recovery-action, and active-manifest")
		os.Exit(2)
	}
	platform, err := stagedHostPlatformForActiveManifestPath(activeManifestPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "staged-update-recover active-manifest: %v\n", err)
		os.Exit(2)
	}
	workflow, err := newHostPlatformStagedReleaseWorkflow(platform, launchctlExecutablePath, systemctlExecutablePath, fsutilExecutablePath, commandExecutablePath, scExecutablePath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "configure C68 Host Installation Manager recovery workflow: %v\n", err)
		os.Exit(2)
	}
	command := hostplatformstagedreleaseupdatedomain.StagedReleaseRecoveryCommand{
		SchemaVersion: "v1", OperationID: operationID, RecoveryID: recoveryID, Action: recoveryAction, RequestedAt: time.Now().UTC().Format(time.RFC3339),
	}
	result, err := workflow.RecoverHostPlatformStagedReleaseUpdate(context.Background(), command, activeManifestPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "execute C68 Host Platform staged update recovery: %v\n", err)
		os.Exit(1)
	}
	if err := json.NewEncoder(os.Stdout).Encode(result); err != nil {
		fmt.Fprintf(os.Stderr, "encode C68 Host Platform recovery receipt: %v\n", err)
		os.Exit(1)
	}
	if result.State != hostplatformstagedreleaseupdatedomain.RecoveryStateSucceeded {
		os.Exit(1)
	}
}

func newHostInstallationWorkflowForPlatform(platform string, pkgutilExecutablePath string, launchctlExecutablePath string, dpkgQueryExecutablePath string, systemctlExecutablePath string, registryExecutablePath string, scExecutablePath string, fsutilExecutablePath string, commandExecutablePath string) (*hostinstallationmanagerapplication.HostInstallationWorkflow, error) {
	common := func(
		footprintObserver hostinstallationmanagerapplication.HostInstallationFootprintObserver,
		releaseActivator hostinstallationmanagerapplication.HostProductReleaseActivator,
		serviceQuiescer hostinstallationmanagerapplication.HostProductServiceQuiescer,
		serviceReconciler hostinstallationmanagerapplication.HostProductServiceReconciler,
		remover hostinstallationmanagerapplication.HostProductRemovalEffects,
	) (*hostinstallationmanagerapplication.HostInstallationWorkflow, error) {
		return hostinstallationmanagerapplication.NewHostInstallationWorkflowWithRemoval(
			hostproductinstallationmanifestfile.HostProductInstallationManifestFileReader{},
			footprintObserver,
			hostinstallationjournalfile.HostInstallationJournalFileStore{},
			hostinstallationreceiptfile.HostInstallationReceiptFileStore{},
			releaseActivator,
			serviceQuiescer,
			serviceReconciler,
			hostproductremovaljournalfile.HostProductRemovalJournalFileStore{},
			hostproductremovalreceiptfile.HostProductRemovalReceiptFileStore{},
			remover,
			hostinstallationmanagerapplication.NewSystemHostInstallationClock(),
		)
	}
	switch platform {
	case "macos":
		footprintObserver, err := macoshostinstallationfootprint.NewMacOSHostInstallationFootprintObserver(pkgutilExecutablePath, launchctlExecutablePath)
		if err != nil {
			return nil, err
		}
		serviceQuiescer, err := macoshostproductservicequiescence.NewMacOSHostProductServiceQuiescer(launchctlExecutablePath)
		if err != nil {
			return nil, err
		}
		serviceReconciler, err := macoshostproductservicereconciliation.NewMacOSHostProductServiceReconciler(launchctlExecutablePath)
		if err != nil {
			return nil, err
		}
		remover, err := macoshostproductremoval.NewMacOSHostProductRemover(pkgutilExecutablePath)
		if err != nil {
			return nil, err
		}
		return common(footprintObserver, macoshostproductreleaseactivation.MacOSHostProductReleaseActivator{}, serviceQuiescer, serviceReconciler, remover)
	case "linux":
		footprintObserver, err := linuxhostinstallationfootprint.NewLinuxHostInstallationFootprintObserver(dpkgQueryExecutablePath, systemctlExecutablePath)
		if err != nil {
			return nil, err
		}
		serviceQuiescer, err := systemdhostproductservicequiescence.NewSystemdHostProductServiceQuiescer(systemctlExecutablePath)
		if err != nil {
			return nil, err
		}
		serviceReconciler, err := systemdhostproductservicereconciliation.NewSystemdHostProductServiceReconciler(systemctlExecutablePath)
		if err != nil {
			return nil, err
		}
		remover, err := linuxhostproductremoval.NewLinuxHostProductRemover(systemctlExecutablePath)
		if err != nil {
			return nil, err
		}
		return common(footprintObserver, linuxhostproductreleaseactivation.LinuxHostProductReleaseActivator{}, serviceQuiescer, serviceReconciler, remover)
	case "windows":
		footprintObserver, err := windowshostinstallationfootprint.NewWindowsHostInstallationFootprintObserver(registryExecutablePath, scExecutablePath, fsutilExecutablePath)
		if err != nil {
			return nil, err
		}
		lifecycle, err := windowshostproductlifecycle.NewWindowsHostProductLifecycle(commandExecutablePath, scExecutablePath)
		if err != nil {
			return nil, err
		}
		return common(footprintObserver, lifecycle, lifecycle, lifecycle, lifecycle)
	default:
		return nil, fmt.Errorf("C48 platform %q is not implemented by this Host Installation Manager binary", platform)
	}
}

func newHostPlatformStagedReleaseWorkflow(platform, launchctlExecutablePath, systemctlExecutablePath, fsutilExecutablePath, commandExecutablePath, scExecutablePath string) (*hostplatformstagedreleaseupdateapplication.Workflow, error) {
	var serviceQuiescer hostplatformstagedreleaseupdateapplication.ServiceQuiescer
	var serviceReconciler hostplatformstagedreleaseupdateapplication.ServiceReconciler
	var activeReleaseReader hostplatformstagedreleaseupdateapplication.ActiveReleaseReader
	var releaseActivator hostplatformstagedreleaseupdateapplication.ReleaseActivator
	switch platform {
	case "macos":
		quiescer, err := macoshostproductservicequiescence.NewMacOSHostProductServiceQuiescer(launchctlExecutablePath)
		if err != nil {
			return nil, err
		}
		reconciler, err := macoshostproductservicereconciliation.NewMacOSHostProductServiceReconciler(launchctlExecutablePath)
		if err != nil {
			return nil, err
		}
		serviceQuiescer, serviceReconciler = quiescer, reconciler
		activeReleaseReader, releaseActivator = unixactivehostrelease.CurrentReleaseReader{}, unixhoststagedreleaseactivation.Activator{}
	case "linux":
		quiescer, err := systemdhostproductservicequiescence.NewSystemdHostProductServiceQuiescer(systemctlExecutablePath)
		if err != nil {
			return nil, err
		}
		reconciler, err := systemdhostproductservicereconciliation.NewSystemdHostProductServiceReconciler(systemctlExecutablePath)
		if err != nil {
			return nil, err
		}
		serviceQuiescer, serviceReconciler = quiescer, reconciler
		activeReleaseReader, releaseActivator = unixactivehostrelease.CurrentReleaseReader{}, unixhoststagedreleaseactivation.Activator{}
	case "windows":
		lifecycle, err := windowshostproductlifecycle.NewWindowsHostProductLifecycle(commandExecutablePath, scExecutablePath)
		if err != nil {
			return nil, err
		}
		reader, err := windowshostactivehostrelease.NewCurrentReleaseReader(fsutilExecutablePath)
		if err != nil {
			return nil, err
		}
		serviceQuiescer, serviceReconciler = lifecycle, lifecycle
		activeReleaseReader, releaseActivator = reader, lifecycle
	default:
		return nil, fmt.Errorf("C68 native staged-update effect is not implemented for platform %q", platform)
	}
	return hostplatformstagedreleaseupdateapplication.NewWorkflow(
		hostplatformreleasearchiveadapter.New(),
		activeReleaseReader,
		hostplatformstagedreleaseoperationfile.Store{},
		hostinstallationtransactionfile.Store{},
		serviceQuiescer,
		hostplatformstagedreleasepublisher.Publisher{},
		releaseActivator,
		serviceReconciler,
		stagedReleaseWallClock{},
	)
}

// C67 paths are product contracts, not platform probes. The CLI uses this
// exact selection only to compose the matching native effect; the reader then
// verifies that the resolved C48 itself declares the same platform.
func stagedHostPlatformForActiveManifestPath(path string) (string, error) {
	switch path {
	case "/Library/Application Support/VitalServerRuntimePlatform/current/installation-manifest.json":
		return "macos", nil
	case "/opt/vitalserver-runtime-platform/current/installation-manifest.json":
		return "linux", nil
	case `C:\ProgramData\VitalServerRuntimePlatform\current\installation-manifest.json`:
		return "windows", nil
	default:
		return "", fmt.Errorf("must be one C67 fixed current-slot C48 path")
	}
}

type stagedReleaseWallClock struct{}

func (stagedReleaseWallClock) Now() string { return time.Now().UTC().Format(time.RFC3339Nano) }
