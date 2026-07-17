// host-updater validates next-updater-only C26 and submits explicit C28
// evidence through C27. Selected platform and Guest adapters own the actual
// layer effects and must produce the evidence document before complete mode.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"net/http"
	"os"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-updater/internal/adapters/hostlocalupdatecompletionpublisher"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-updater/internal/adapters/stagedupdateinvocationfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-updater/internal/adapters/updateexecutionreportfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-updater/internal/hostupdaterdomain"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-updater/internal/hostupdaterstagedupdatecompletionapplication"
)

func main() {
	mode := flag.String("mode", "plan", "host updater mode: plan or complete")
	invocationPath := flag.String("invocation", "", "required C30 staged update invocation path")
	reportPath := flag.String("report", "", "required C28 update execution report path for complete mode")
	completionEndpoint := flag.String("completion-endpoint", "", "required Host-local completion endpoint origin for complete mode")
	completionTimeout := flag.Duration("completion-timeout", 30*time.Second, "Host-local completion HTTP timeout")
	flag.Parse()
	switch *mode {
	case "plan":
		runPlan(*invocationPath)
	case "complete":
		runComplete(*invocationPath, *reportPath, *completionEndpoint, *completionTimeout)
	default:
		fmt.Fprintln(os.Stderr, "host updater mode is unsupported")
		os.Exit(2)
	}
}

func runPlan(invocationPath string) {
	input, err := stagedupdateinvocationfile.ReadStagedProductUpdatePlanningInput(invocationPath)
	if err != nil {
		fmt.Fprintf(os.Stderr, "read staged update input: %v\n", err)
		os.Exit(2)
	}
	plan, err := hostupdaterdomain.PlanStagedProductUpdateExecution(input)
	if err != nil {
		fmt.Fprintf(os.Stderr, "validate product update specification: %v\n", err)
		os.Exit(1)
	}
	if err := json.NewEncoder(os.Stdout).Encode(plan); err != nil {
		fmt.Fprintf(os.Stderr, "encode execution plan: %v\n", err)
		os.Exit(1)
	}
}

func runComplete(invocationPath string, reportPath string, completionEndpoint string, completionTimeout time.Duration) {
	if completionTimeout <= 0 {
		fmt.Fprintln(os.Stderr, "Host-local completion timeout must be positive")
		os.Exit(2)
	}
	publisher, err := hostlocalupdatecompletionpublisher.NewHostLocalStagedProductUpdateCompletionHTTPPublisher(&http.Client{Timeout: completionTimeout})
	if err != nil {
		fmt.Fprintf(os.Stderr, "configure Host-local update completion client: %v\n", err)
		os.Exit(2)
	}
	workflow, err := hostupdaterstagedupdatecompletionapplication.NewStagedProductUpdateCompletionWorkflow(stagedupdateinvocationfile.StagedProductUpdateInvocationFileReader{}, updateexecutionreportfile.StagedProductUpdateExecutionReportFileReader{}, publisher)
	if err != nil {
		fmt.Fprintf(os.Stderr, "configure update completion workflow: %v\n", err)
		os.Exit(2)
	}
	command, err := workflow.PublishStagedProductUpdateCompletion(context.Background(), invocationPath, reportPath, completionEndpoint)
	if err != nil {
		fmt.Fprintf(os.Stderr, "complete staged update: %v\n", err)
		os.Exit(1)
	}
	if err := json.NewEncoder(os.Stdout).Encode(command); err != nil {
		fmt.Fprintf(os.Stderr, "encode completed update command: %v\n", err)
		os.Exit(1)
	}
}
