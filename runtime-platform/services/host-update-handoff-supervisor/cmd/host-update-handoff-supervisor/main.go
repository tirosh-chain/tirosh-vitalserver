// host-update-handoff-supervisor consumes explicit C31 queue entries and
// starts only the byte-verified C25-selected next updater. It does not parse
// C26 and never treats a child process exit as an update-success state.
package main

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"os"
	"os/signal"
	"path/filepath"
	"sort"
	"strings"
	"time"

	"github.com/tirosh-chain/vitalserver-runtime-platform/host-update-handoff-supervisor/internal/adapters/hostlocalupdatecoordination"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-update-handoff-supervisor/internal/adapters/hostupdatehandoffconfigurationfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-update-handoff-supervisor/internal/adapters/hostupdatehandoffdispatchreceiptfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-update-handoff-supervisor/internal/adapters/stagednextupdaterdispatchinputfile"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-update-handoff-supervisor/internal/adapters/stagednextupdaterprocess"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-update-handoff-supervisor/internal/hostupdatehandoffsupervisorapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/host-update-handoff-supervisor/internal/hostupdatehandoffsupervisordomain"
)

type wallClock struct{}

func (wallClock) Now() time.Time { return time.Now() }

type command struct {
	configuration hostupdatehandoffsupervisordomain.HostUpdateHandoffSupervisorConfiguration
	workflow      *hostupdatehandoffsupervisorapplication.HostUpdateHandoffSupervisorWorkflow
}

func main() {
	configurationPath := flag.String("configuration", "", "required absolute C56 Host update handoff supervisor configuration path")
	mode := flag.String("mode", "dispatch-one", "operation: dispatch-one, drain, or service")
	handoffPath := flag.String("handoff", "", "required absolute C31 handoff queue entry path for dispatch-one")
	attemptID := flag.String("attempt-id", "", "required C57 immutable dispatch-attempt identifier for dispatch-one")
	flag.Parse()

	configuration, err := hostupdatehandoffconfigurationfile.ReadHostUpdateHandoffSupervisorConfiguration(*configurationPath)
	if err != nil {
		fatal(2, "read C56 supervisor configuration", err)
	}
	coordination := hostlocalupdatecoordination.Client{}
	workflow, err := hostupdatehandoffsupervisorapplication.NewHostUpdateHandoffSupervisorWorkflow(stagednextupdaterdispatchinputfile.StagedNextUpdaterDispatchInputFileReader{}, stagednextupdaterprocess.StagedNextUpdaterProcessRunner{}, coordination, coordination, wallClock{})
	if err != nil {
		fatal(2, "configure C31 handoff supervisor", err)
	}
	command := command{configuration: configuration, workflow: workflow}
	switch *mode {
	case "dispatch-one":
		if *handoffPath == "" || *attemptID == "" {
			fatal(2, "validate dispatch-one arguments", fmt.Errorf("--handoff and --attempt-id are required"))
		}
		receipt, err := command.dispatchOne(context.Background(), *attemptID, *handoffPath)
		if err != nil {
			fatal(1, "dispatch C31 handoff", err)
		}
		writeReceipt(receipt)
	case "drain":
		if *handoffPath != "" || *attemptID != "" {
			fatal(2, "validate drain arguments", fmt.Errorf("--handoff and --attempt-id are not valid with --mode drain"))
		}
		receipts, err := command.drain(context.Background())
		if err != nil {
			fatal(1, "drain C31 handoff queue", err)
		}
		for _, receipt := range receipts {
			writeReceipt(receipt)
		}
	case "service":
		if *handoffPath != "" || *attemptID != "" {
			fatal(2, "validate service arguments", fmt.Errorf("--handoff and --attempt-id are not valid with --mode service"))
		}
		runtimeContext, stop := signal.NotifyContext(context.Background(), os.Interrupt)
		defer stop()
		if err := command.serve(runtimeContext); err != nil {
			fatal(1, "serve C31 handoff queue", err)
		}
	default:
		fatal(2, "validate operation mode", fmt.Errorf("unsupported mode %q", *mode))
	}
}

func (command command) dispatchOne(ctx context.Context, attemptID string, handoffPath string) (hostupdatehandoffsupervisordomain.HostUpdateHandoffDispatchReceipt, error) {
	if existing, exists, err := hostupdatehandoffdispatchreceiptfile.ReadHostUpdateHandoffDispatchReceipt(command.configuration.ExecutionEvidenceDirectory, attemptID); err != nil {
		return hostupdatehandoffsupervisordomain.HostUpdateHandoffDispatchReceipt{}, fmt.Errorf("read C57 dispatch receipt: %w", err)
	} else if exists {
		return existing, nil
	}
	receipt, err := command.workflow.Dispatch(ctx, command.configuration, attemptID, handoffPath)
	if err != nil {
		return hostupdatehandoffsupervisordomain.HostUpdateHandoffDispatchReceipt{}, err
	}
	if _, err := hostupdatehandoffdispatchreceiptfile.WriteHostUpdateHandoffDispatchReceipt(command.configuration.ExecutionEvidenceDirectory, receipt); err != nil {
		return hostupdatehandoffsupervisordomain.HostUpdateHandoffDispatchReceipt{}, fmt.Errorf("write C57 dispatch receipt: %w", err)
	}
	return receipt, nil
}

// drain processes direct C31 queue entries in lexical order.  The automatic
// attempt ID is a digest of the immutable handoff bytes, so service restart is
// idempotent. A failed attempt is retained as C57 evidence; an operator must
// create a new explicitly named attempt to retry it rather than an implicit
// timer retry changing its meaning.
func (command command) drain(ctx context.Context) ([]hostupdatehandoffsupervisordomain.HostUpdateHandoffDispatchReceipt, error) {
	queue, err := directRegularJSONFiles(command.configuration.HandoffQueueDirectory)
	if err != nil {
		return nil, err
	}
	receipts := make([]hostupdatehandoffsupervisordomain.HostUpdateHandoffDispatchReceipt, 0, len(queue))
	for _, handoffPath := range queue {
		contents, err := readRegularFile(handoffPath)
		if err != nil {
			return nil, fmt.Errorf("read C31 queue entry %s: %w", handoffPath, err)
		}
		receipt, err := command.dispatchOne(ctx, automaticAttemptID(contents), handoffPath)
		if err != nil {
			return nil, fmt.Errorf("dispatch C31 queue entry %s: %w", handoffPath, err)
		}
		receipts = append(receipts, receipt)
	}
	return receipts, nil
}

// serve keeps the C31 queue consumer alive for an OS service manager. The
// C56 interval is mandatory; this process does not invent a retry cadence.
// A retained C57 receipt makes each unchanged C31 entry idempotent across
// polls, including a terminal failed receipt.
func (command command) serve(ctx context.Context) error {
	return runServiceDrainLoop(ctx, time.Duration(command.configuration.ServicePollIntervalMilliseconds)*time.Millisecond, func(ctx context.Context) error {
		_, err := command.drain(ctx)
		return err
	})
}

func runServiceDrainLoop(ctx context.Context, pollInterval time.Duration, drain func(context.Context) error) error {
	if pollInterval <= 0 || drain == nil {
		return fmt.Errorf("C56 service poll interval and drain operation are required")
	}
	for {
		if ctx.Err() != nil {
			return nil
		}
		if err := drain(ctx); err != nil {
			return err
		}
		timer := time.NewTimer(pollInterval)
		select {
		case <-ctx.Done():
			if !timer.Stop() {
				<-timer.C
			}
			return nil
		case <-timer.C:
		}
	}
}

func directRegularJSONFiles(directory string) ([]string, error) {
	info, err := os.Lstat(directory)
	if err != nil || !info.IsDir() || info.Mode()&os.ModeSymlink != 0 {
		return nil, fmt.Errorf("C31 handoff queue is missing, non-directory, or a symbolic link")
	}
	entries, err := os.ReadDir(directory)
	if err != nil {
		return nil, err
	}
	paths := make([]string, 0, len(entries))
	for _, entry := range entries {
		if !strings.HasSuffix(entry.Name(), ".json") {
			continue
		}
		path := filepath.Join(directory, entry.Name())
		entryInfo, err := os.Lstat(path)
		if err != nil || !entryInfo.Mode().IsRegular() || entryInfo.Mode()&os.ModeSymlink != 0 {
			return nil, fmt.Errorf("C31 queue entry %s is missing, non-regular, or a symbolic link", entry.Name())
		}
		paths = append(paths, path)
	}
	sort.Strings(paths)
	return paths, nil
}

func automaticAttemptID(contents []byte) string {
	digest := sha256.Sum256(contents)
	return "automatic-" + hex.EncodeToString(digest[:])
}

func readRegularFile(path string) ([]byte, error) {
	info, err := os.Lstat(path)
	if err != nil || !info.Mode().IsRegular() || info.Mode()&os.ModeSymlink != 0 {
		return nil, fmt.Errorf("file is missing, non-regular, or a symbolic link")
	}
	file, err := os.Open(path)
	if err != nil {
		return nil, err
	}
	defer file.Close()
	contents, err := io.ReadAll(io.LimitReader(file, 1<<20))
	if err != nil {
		return nil, err
	}
	return contents, nil
}

func writeReceipt(receipt hostupdatehandoffsupervisordomain.HostUpdateHandoffDispatchReceipt) {
	if err := json.NewEncoder(os.Stdout).Encode(receipt); err != nil {
		fatal(1, "encode C57 dispatch receipt", err)
	}
	if receipt.State != "completion-submitted" {
		os.Exit(1)
	}
}

func fatal(status int, action string, err error) {
	if err != nil && !errors.Is(err, flag.ErrHelp) {
		fmt.Fprintf(os.Stderr, "%s: %v\\n", action, err)
	}
	os.Exit(status)
}
