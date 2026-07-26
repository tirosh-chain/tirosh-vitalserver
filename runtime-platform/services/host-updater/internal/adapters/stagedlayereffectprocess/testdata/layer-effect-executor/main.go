package main

import (
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"os"
	"path/filepath"
)

const fixtureExecutorID = "guest-runtime-executor"
const fixtureConfiguration = `{"schemaVersion":"v1","executorId":"guest-runtime-executor"}`
const fixtureArtifact = "guest-runtime-artifact"

type receipt struct {
	SchemaVersion    string   `json:"schemaVersion"`
	UpdateID         string   `json:"updateId"`
	Layer            string   `json:"layer"`
	EffectExecutorID string   `json:"effectExecutorId"`
	Operation        string   `json:"operation"`
	ArtifactSHA256   string   `json:"artifactSha256"`
	State            string   `json:"state"`
	ObservedAt       string   `json:"observedAt"`
	Evidence         evidence `json:"evidence"`
}

type evidence struct {
	Kind string `json:"kind"`
	ID   string `json:"id"`
}

func main() {
	if len(os.Args) != 19 ||
		os.Args[1] != "--protocol-version" || os.Args[2] != "v1" ||
		os.Args[3] != "--effect-executor-id" || os.Args[4] != fixtureExecutorID ||
		os.Args[5] != "--effect-configuration-path" ||
		os.Args[7] != "--receipt-path" ||
		os.Args[9] != "--update-id" || os.Args[10] != "update-020" ||
		os.Args[11] != "--layer" || os.Args[12] != "guest-runtime" ||
		os.Args[13] != "--operation" || os.Args[14] != "apply" ||
		os.Args[15] != "--artifact-path" ||
		os.Args[17] != "--artifact-sha256" {
		os.Exit(73)
	}
	effectConfigurationPath := os.Args[6]
	receiptPath := os.Args[8]
	artifactPath := os.Args[16]
	if !filepath.IsAbs(effectConfigurationPath) ||
		filepath.Base(effectConfigurationPath) != "guest-runtime.json" ||
		!filepath.IsAbs(receiptPath) ||
		filepath.Ext(receiptPath) != ".json" ||
		!filepath.IsAbs(artifactPath) ||
		filepath.Base(artifactPath) != "guest-runtime.tar" {
		os.Exit(73)
	}
	configurationContents, err := os.ReadFile(effectConfigurationPath)
	if err != nil || string(configurationContents) != fixtureConfiguration {
		os.Exit(73)
	}
	artifactContents, err := os.ReadFile(artifactPath)
	if err != nil || string(artifactContents) != fixtureArtifact {
		os.Exit(73)
	}
	artifactDigest := sha256.Sum256(artifactContents)
	artifactSHA256 := hex.EncodeToString(artifactDigest[:])
	if os.Args[18] != artifactSHA256 {
		os.Exit(73)
	}
	document := receipt{
		SchemaVersion:    "v1",
		UpdateID:         os.Args[10],
		Layer:            os.Args[12],
		EffectExecutorID: os.Args[4],
		Operation:        os.Args[14],
		ArtifactSHA256:   artifactSHA256,
		State:            "succeeded",
		ObservedAt:       "2026-07-19T00:00:00Z",
		Evidence: evidence{
			Kind: "layer-effect-receipt",
			ID:   os.Args[12] + "-" + os.Args[14],
		},
	}
	contents, err := json.Marshal(document)
	if err != nil {
		os.Exit(74)
	}
	contents = append(contents, '\n')
	if err := os.WriteFile(receiptPath, contents, 0o600); err != nil {
		os.Exit(75)
	}
}
