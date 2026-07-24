package vitalfilereplayspoolsqlite

import (
	"fmt"
	"os"
	"path/filepath"

	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimeapplication"
	"github.com/tirosh-chain/vitalserver-runtime-platform/guest-runtime/internal/guestruntimedomain"
)

type Factory struct {
	rootDirectory string
}

func NewFactory(rootDirectory string) (*Factory, error) {
	if rootDirectory == "" || !filepath.IsAbs(rootDirectory) {
		return nil, fmt.Errorf("Vital replay spool root directory must be absolute")
	}
	return &Factory{rootDirectory: rootDirectory}, nil
}

func (factory *Factory) NewSpoolWriter(
	replayID string,
) (guestruntimeapplication.GuestRuntimeVitalFileReplaySpoolWriter, error) {
	return NewWriter(factory.rootDirectory, replayID)
}

func (factory *Factory) ReadFinalizedSpoolReceipt(
	replayID string,
) (guestruntimedomain.VitalFileReplaySpoolReceipt, error) {
	if !guestruntimedomain.ValidIdentifier(replayID) {
		return guestruntimedomain.VitalFileReplaySpoolReceipt{},
			fmt.Errorf("Vital replay identifier is invalid")
	}
	finalDirectory := filepath.Join(factory.rootDirectory, replayID)
	if _, err := os.Stat(finalDirectory); os.IsNotExist(err) {
		return guestruntimedomain.VitalFileReplaySpoolReceipt{},
			guestruntimeapplication.ErrGuestRuntimeOwnedResourceNotFound
	} else if err != nil {
		return guestruntimedomain.VitalFileReplaySpoolReceipt{}, err
	}
	receipt, err := readReceipt(filepath.Join(finalDirectory, spoolReceiptFileName))
	if err != nil {
		return guestruntimedomain.VitalFileReplaySpoolReceipt{}, err
	}
	reader, err := OpenReader(
		factory.rootDirectory,
		replayID,
		receipt,
		GapPolicyOmitTrack,
	)
	if err != nil {
		return guestruntimedomain.VitalFileReplaySpoolReceipt{}, err
	}
	if err := reader.Close(); err != nil {
		return guestruntimedomain.VitalFileReplaySpoolReceipt{}, err
	}
	return receipt, nil
}

func (factory *Factory) OpenSpoolReader(
	replayID string,
	receipt guestruntimedomain.VitalFileReplaySpoolReceipt,
	gapPolicy string,
) (guestruntimeapplication.GuestRuntimeVitalFileReplaySpoolReader, error) {
	return OpenReader(
		factory.rootDirectory,
		replayID,
		receipt,
		gapPolicy,
	)
}

var _ guestruntimeapplication.GuestRuntimeVitalFileReplaySpoolFactory = (*Factory)(nil)
