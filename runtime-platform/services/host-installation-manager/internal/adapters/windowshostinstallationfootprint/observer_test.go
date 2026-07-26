package windowshostinstallationfootprint

import (
	"context"
	"testing"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-installation-manager/internal/hostinstallationmanagerdomain"
)

type commandRunnerFake struct{ results map[string]CommandResult }

func (fake commandRunnerFake) RunWindowsHostInstallationCommand(_ context.Context, executable string, arguments ...string) (CommandResult, error) {
	key := executable
	for _, argument := range arguments {
		key += "|" + argument
	}
	return fake.results[key], nil
}

func TestObserveHostPackageReceiptReadsExactMSIProductCodeRegistration(t *testing.T) {
	productCode := "{12345678-1234-1234-1234-1234567890AB}"
	observer, err := NewWindowsHostInstallationFootprintObserverWithCommandRunner("reg.exe", "sc.exe", "fsutil.exe", commandRunnerFake{results: map[string]CommandResult{
		`reg.exe|query|HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\` + productCode + `|/v|DisplayVersion`: {Stdout: "    DisplayVersion    REG_SZ    0.2.0\r\n"},
	}})
	if err != nil {
		t.Fatal(err)
	}
	receipt := observer.ObserveHostPackageReceipt(context.Background(), hostinstallationmanagerdomain.HostProductPackageIdentity{Identifier: "com.tirosh.vitalserver.runtime-platform", PackageManagerIdentifier: productCode})
	if receipt.State != "installed" || receipt.PackageManagerReceiptState != "installed" || receipt.ProductVersion != "0.2.0" || receipt.Issue != nil {
		t.Fatalf("receipt=%+v", receipt)
	}
}

func TestObserveHostPackageReceiptKeepsMissingMSIRegistrationAbsent(t *testing.T) {
	productCode := "{12345678-1234-1234-1234-1234567890AB}"
	observer, err := NewWindowsHostInstallationFootprintObserverWithCommandRunner("reg.exe", "sc.exe", "fsutil.exe", commandRunnerFake{results: map[string]CommandResult{
		`reg.exe|query|HKLM\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\` + productCode + `|/v|DisplayVersion`:             {ExitCode: 1},
		`reg.exe|query|HKLM\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\` + productCode + `|/v|DisplayVersion`: {ExitCode: 1},
	}})
	if err != nil {
		t.Fatal(err)
	}
	receipt := observer.ObserveHostPackageReceipt(context.Background(), hostinstallationmanagerdomain.HostProductPackageIdentity{Identifier: "com.tirosh.vitalserver.runtime-platform", PackageManagerIdentifier: productCode})
	if receipt.State != "absent" || receipt.Issue != nil {
		t.Fatalf("receipt=%+v", receipt)
	}
}

func TestObserveHostServiceRegistrationRequiresExactDeclaredSCMConfiguration(t *testing.T) {
	service := hostinstallationmanagerdomain.HostProductRequiredService{
		Role: "host-agent", Manager: "windows-scm", Name: "vitalserver-host-agent",
		WindowsSCMRegistration: &hostinstallationmanagerdomain.HostProductWindowsSCMRegistration{ExecutablePath: `C:\ProgramData\VitalServerRuntimePlatform\current\bin\host-agent.exe`, Arguments: []string{"--service"}, StartMode: "automatic", Account: "LocalSystem"},
	}
	observer, err := NewWindowsHostInstallationFootprintObserverWithCommandRunner("reg.exe", "sc.exe", "fsutil.exe", commandRunnerFake{results: map[string]CommandResult{
		"sc.exe|qc|vitalserver-host-agent": {Stdout: "[SC] QueryServiceConfig SUCCESS\n\nBINARY_PATH_NAME   : C:\\ProgramData\\VitalServerRuntimePlatform\\current\\bin\\host-agent.exe --service\nSTART_TYPE         : 2   AUTO_START\nSERVICE_START_NAME : LocalSystem\n"},
	}})
	if err != nil {
		t.Fatal(err)
	}
	observation := observer.ObserveHostServiceRegistration(context.Background(), service)
	if observation.State != "registered" || observation.Issue != nil {
		t.Fatalf("observation=%+v", observation)
	}
}

func TestObserveHostServiceRegistrationDoesNotTreatDivergedCommandAsRegistered(t *testing.T) {
	service := hostinstallationmanagerdomain.HostProductRequiredService{
		Role: "host-agent", Manager: "windows-scm", Name: "vitalserver-host-agent",
		WindowsSCMRegistration: &hostinstallationmanagerdomain.HostProductWindowsSCMRegistration{ExecutablePath: `C:\ProgramData\VitalServerRuntimePlatform\current\bin\host-agent.exe`, Arguments: []string{"--service"}, StartMode: "automatic", Account: "LocalSystem"},
	}
	observer, err := NewWindowsHostInstallationFootprintObserverWithCommandRunner("reg.exe", "sc.exe", "fsutil.exe", commandRunnerFake{results: map[string]CommandResult{
		"sc.exe|qc|vitalserver-host-agent": {Stdout: "BINARY_PATH_NAME   : C:\\unexpected.exe\nSTART_TYPE         : 2   AUTO_START\nSERVICE_START_NAME : LocalSystem\n"},
	}})
	if err != nil {
		t.Fatal(err)
	}
	observation := observer.ObserveHostServiceRegistration(context.Background(), service)
	if observation.State != "failed" || observation.Issue == nil || observation.Issue.Code != "windows-scm-service-registration-diverged" {
		t.Fatalf("observation=%+v", observation)
	}
}
