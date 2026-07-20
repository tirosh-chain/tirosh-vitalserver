// host-updater validates next-updater-only C26, executes its C26-declared
// fixed-protocol layer effects into C55/C28 evidence, and submits C28 through
// C27. It never turns a command exit or log into an update outcome.
package main

import (
	"context"
	"encoding/json"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-updater/internal/adapters/hostlocalupdatecompletionpublisher"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-updater/internal/adapters/stagedlayereffectprocess"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-updater/internal/adapters/stagedupdateinvocationfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-updater/internal/adapters/updateexecutionreportfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-updater/internal/hostupdaterdomain"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-updater/internal/hostupdaterlayerexecutionapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-updater/internal/hostupdaterstagedupdatecompletionapplication"
)

type wallClock struct{}

func (wallClock) Now() time.Time { return time.Now() }

func main() {
	mode := flag.String("mode", "plan", "host updater mode: plan, execute, or complete")
	invocationPath := flag.String("invocation", "", "required C30 staged update invocation path")
	reportPath := flag.String("report", "", "required absolute C28 update execution report path for execute modes")
	layerEffectReceiptDirectory := flag.String("layer-effect-receipt-directory", "", "required absolute Host-owned C55 receipt directory for execute modes")
	completionDescriptorPath := flag.String("completion-descriptor", "", "required absolute C52 Host-local administration descriptor path for complete mode")
	layerEffectTimeout := flag.Duration("layer-effect-timeout", 0, "required positive timeout for the C26 layer-effect execution workflow in execute mode")
	completionTimeout := flag.Duration("completion-timeout", 30*time.Second, "Host-local completion HTTP timeout")
	flag.Parse()
	switch *mode {
	case "plan":
		runPlan(*invocationPath)
	case "execute":
		runExecute(*invocationPath, *reportPath, *layerEffectReceiptDirectory, *layerEffectTimeout)
	case "complete":
		runComplete(*invocationPath, *reportPath, *completionDescriptorPath, *completionTimeout)
	default:
		fmt.Fprintln(os.Stderr, "host updater mode is unsupported")
		os.Exit(2)
	}
}

// runExecute owns C26 layer effects and the atomic C28 outcome only.  It must
// not submit C27: when C28 is durable but its later C27 transport is
// unavailable, recovery must use complete mode rather than replaying effects.
func runExecute(invocationPath string, reportPath string, layerEffectReceiptDirectory string, layerEffectTimeout time.Duration) {
	report, err := executeStagedProductUpdate(invocationPath, reportPath, layerEffectReceiptDirectory, layerEffectTimeout)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(1)
	}
	if err := json.NewEncoder(os.Stdout).Encode(report); err != nil {
		fmt.Fprintf(os.Stderr, "encode executed update report: %v\n", err)
		os.Exit(1)
	}
}

// runComplete is the explicit C27 settlement entry point after an update
// execution has already persisted C28. Callers must not treat a written C28
// as a settled Host update.
func runComplete(invocationPath string, reportPath string, completionDescriptorPath string, completionTimeout time.Duration) {
	if completionDescriptorPath == "" || !filepath.IsAbs(completionDescriptorPath) || completionTimeout <= 0 {
		fmt.Fprintln(os.Stderr, "complete mode requires an absolute C52 descriptor and a positive completion timeout")
		os.Exit(2)
	}
	publisher, err := hostlocalupdatecompletionpublisher.NewHostLocalDescriptorStagedProductUpdateCompletionPublisher(completionDescriptorPath, completionTimeout)
	if err != nil {
		fmt.Fprintf(os.Stderr, "configure C52 completion publisher: %v\n", err)
		os.Exit(2)
	}
	completionWorkflow, err := hostupdaterstagedupdatecompletionapplication.NewStagedProductUpdateCompletionWorkflow(stagedupdateinvocationfile.StagedProductUpdateInvocationFileReader{}, updateexecutionreportfile.StagedProductUpdateExecutionReportFileReader{}, publisher)
	if err != nil {
		fmt.Fprintf(os.Stderr, "configure C27 completion workflow: %v\n", err)
		os.Exit(2)
	}
	command, err := completionWorkflow.PublishStagedProductUpdateCompletion(context.Background(), invocationPath, reportPath, publisher.EndpointAddress())
	if err != nil {
		fmt.Fprintf(os.Stderr, "complete staged product update: %v\n", err)
		os.Exit(1)
	}
	if err := json.NewEncoder(os.Stdout).Encode(command); err != nil {
		fmt.Fprintf(os.Stderr, "encode completed update command: %v\n", err)
		os.Exit(1)
	}
}

func executeStagedProductUpdate(invocationPath string, reportPath string, layerEffectReceiptDirectory string, layerEffectTimeout time.Duration) (hostupdaterdomain.StagedProductUpdateExecutionReport, error) {
	if invocationPath == "" || !filepath.IsAbs(invocationPath) || reportPath == "" || !filepath.IsAbs(reportPath) || layerEffectReceiptDirectory == "" || !filepath.IsAbs(layerEffectReceiptDirectory) || layerEffectTimeout <= 0 {
		return hostupdaterdomain.StagedProductUpdateExecutionReport{}, fmt.Errorf("execute mode requires absolute invocation, report, C55 receipt directory, and a positive layer-effect timeout")
	}
	effectExecutor, err := stagedlayereffectprocess.NewStagedLayerEffectProcessExecutor(stagedlayereffectprocess.StagedLayerEffectProcessExecutorConfig{StagingDirectory: filepath.Dir(invocationPath), ReceiptDirectory: layerEffectReceiptDirectory})
	if err != nil {
		return hostupdaterdomain.StagedProductUpdateExecutionReport{}, fmt.Errorf("configure C26 layer effect executor: %w", err)
	}
	workflow, err := hostupdaterlayerexecutionapplication.NewStagedProductUpdateLayerExecutionWorkflow(
		stagedupdateinvocationfile.StagedProductUpdateInvocationFileReader{},
		effectExecutor,
		wallClock{},
	)
	if err != nil {
		return hostupdaterdomain.StagedProductUpdateExecutionReport{}, fmt.Errorf("configure layer execution workflow: %w", err)
	}
	ctx, cancel := context.WithTimeout(context.Background(), layerEffectTimeout)
	defer cancel()
	report, err := workflow.ExecuteStagedProductUpdate(ctx, invocationPath)
	if err != nil {
		return hostupdaterdomain.StagedProductUpdateExecutionReport{}, fmt.Errorf("execute staged product update: %w", err)
	}
	if err := updateexecutionreportfile.WriteStagedProductUpdateExecutionReport(reportPath, report); err != nil {
		return hostupdaterdomain.StagedProductUpdateExecutionReport{}, fmt.Errorf("write C28 update execution report: %w", err)
	}
	return report, nil
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
