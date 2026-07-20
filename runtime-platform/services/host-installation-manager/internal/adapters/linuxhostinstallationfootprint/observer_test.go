package linuxhostinstallationfootprint

import (
	"context"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

type commandRunnerFake struct{ results map[string]CommandResult }

func (fake commandRunnerFake) RunLinuxHostInstallationCommand(_ context.Context, executable string, arguments ...string) (CommandResult, error) {
	key := executable
	for _, argument := range arguments {
		key += "|" + argument
	}
	return fake.results[key], nil
}

func TestObserveHostPackageReceiptRequiresInstalledStatusAndVersion(t *testing.T) {
	observer, err := NewLinuxHostInstallationFootprintObserverWithCommandRunner("dpkg-query", "systemctl", commandRunnerFake{results: map[string]CommandResult{
		"dpkg-query|-W|-f=${Status}\\n${Version}\\n|com.tirosh.vitalserver.runtime-platform": {Stdout: "install ok installed\n0.2.0-dev\n"},
	}})
	if err != nil {
		t.Fatal(err)
	}
	receipt := observer.ObserveHostPackageReceipt(context.Background(), hostinstallationmanagerdomain.HostProductPackageIdentity{Identifier: "com.tirosh.vitalserver.runtime-platform"})
	if receipt.State != "installed" || receipt.PackageManagerReceiptState != "installed" || receipt.ProductVersion != "0.2.0-dev" {
		t.Fatalf("receipt=%+v", receipt)
	}
}

func TestObserveHostPackageReceiptTreatsDpkgConfigFilesRecordAsNoInstalledProductReceipt(t *testing.T) {
	observer, err := NewLinuxHostInstallationFootprintObserverWithCommandRunner("dpkg-query", "systemctl", commandRunnerFake{results: map[string]CommandResult{
		"dpkg-query|-W|-f=${Status}\\n${Version}\\n|com.tirosh.vitalserver.runtime-platform": {Stdout: "deinstall ok config-files\n0.2.0-dev\n"},
	}})
	if err != nil {
		t.Fatal(err)
	}
	receipt := observer.ObserveHostPackageReceipt(context.Background(), hostinstallationmanagerdomain.HostProductPackageIdentity{Identifier: "com.tirosh.vitalserver.runtime-platform"})
	if receipt.State != "absent" || receipt.PackageManagerReceiptState != "configuration-retained" || receipt.ProductVersion != "" || receipt.Issue != nil {
		t.Fatalf("receipt=%+v", receipt)
	}
}

func TestObserveHostPackageReceiptReportsUnpackedPayloadExplicitly(t *testing.T) {
	observer, err := NewLinuxHostInstallationFootprintObserverWithCommandRunner("dpkg-query", "systemctl", commandRunnerFake{results: map[string]CommandResult{
		"dpkg-query|-W|-f=${Status}\\n${Version}\\n|com.tirosh.vitalserver.runtime-platform": {Stdout: "install ok unpacked\n0.2.0-dev\n"},
	}})
	if err != nil {
		t.Fatal(err)
	}
	receipt := observer.ObserveHostPackageReceipt(context.Background(), hostinstallationmanagerdomain.HostProductPackageIdentity{Identifier: "com.tirosh.vitalserver.runtime-platform"})
	if receipt.State != "installed" || receipt.PackageManagerReceiptState != "unpacked" || receipt.ProductVersion != "0.2.0-dev" || receipt.Issue != nil {
		t.Fatalf("receipt=%+v", receipt)
	}
}

func TestObserveHostPackageReceiptReportsDpkgPostinstConfigurationExplicitly(t *testing.T) {
	observer, err := NewLinuxHostInstallationFootprintObserverWithCommandRunner("dpkg-query", "systemctl", commandRunnerFake{results: map[string]CommandResult{
		"dpkg-query|-W|-f=${Status}\\n${Version}\\n|com.tirosh.vitalserver.runtime-platform": {Stdout: "install ok half-configured\n0.2.0-dev\n"},
	}})
	if err != nil {
		t.Fatal(err)
	}
	receipt := observer.ObserveHostPackageReceipt(context.Background(), hostinstallationmanagerdomain.HostProductPackageIdentity{Identifier: "com.tirosh.vitalserver.runtime-platform"})
	if receipt.State != "installed" || receipt.PackageManagerReceiptState != "configuring" || receipt.ProductVersion != "0.2.0-dev" || receipt.Issue != nil {
		t.Fatalf("receipt=%+v", receipt)
	}
}

func TestObserveHostPackageReceiptReportsDpkgPreRemovalTransitionExplicitly(t *testing.T) {
	observer, err := NewLinuxHostInstallationFootprintObserverWithCommandRunner("dpkg-query", "systemctl", commandRunnerFake{results: map[string]CommandResult{
		"dpkg-query|-W|-f=${Status}\\n${Version}\\n|com.tirosh.vitalserver.runtime-platform": {Stdout: "deinstall ok half-configured\n0.2.0-dev\n"},
	}})
	if err != nil {
		t.Fatal(err)
	}
	receipt := observer.ObserveHostPackageReceipt(context.Background(), hostinstallationmanagerdomain.HostProductPackageIdentity{Identifier: "com.tirosh.vitalserver.runtime-platform"})
	if receipt.State != "installed" || receipt.PackageManagerReceiptState != "removing" || receipt.ProductVersion != "0.2.0-dev" || receipt.Issue != nil {
		t.Fatalf("receipt=%+v", receipt)
	}
}

func TestObserveHostPackageReceiptReportsDpkgPayloadRemovalExplicitly(t *testing.T) {
	observer, err := NewLinuxHostInstallationFootprintObserverWithCommandRunner("dpkg-query", "systemctl", commandRunnerFake{results: map[string]CommandResult{
		"dpkg-query|-W|-f=${Status}\\n${Version}\\n|com.tirosh.vitalserver.runtime-platform": {Stdout: "deinstall ok half-installed\n0.2.0-dev\n"},
	}})
	if err != nil {
		t.Fatal(err)
	}
	receipt := observer.ObserveHostPackageReceipt(context.Background(), hostinstallationmanagerdomain.HostProductPackageIdentity{Identifier: "com.tirosh.vitalserver.runtime-platform"})
	if receipt.State != "installed" || receipt.PackageManagerReceiptState != "removed" || receipt.ProductVersion != "0.2.0-dev" || receipt.Issue != nil {
		t.Fatalf("receipt=%+v", receipt)
	}
}

func TestObserveHostServiceRegistrationKeepsUnexpectedLoadStateAsFailure(t *testing.T) {
	observer, err := NewLinuxHostInstallationFootprintObserverWithCommandRunner("dpkg-query", "systemctl", commandRunnerFake{results: map[string]CommandResult{
		"systemctl|show|--property=LoadState|--value|vitalserver-host-agent.service": {Stdout: "masked\n"},
	}})
	if err != nil {
		t.Fatal(err)
	}
	service := observer.ObserveHostServiceRegistration(context.Background(), hostinstallationmanagerdomain.HostProductRequiredService{Role: "host-agent", Manager: "systemd", Name: "vitalserver-host-agent.service", DefinitionPath: "/missing.service", DefinitionSHA256: "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"})
	if service.State != "failed" || service.Issue == nil || service.Issue.Code != "linux-service-observation-decode-failed" {
		t.Fatalf("service=%+v", service)
	}
}
