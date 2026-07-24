"""Tests for the explicit C79 Vital replay corpus gate."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import tempfile
import unittest

from tooling import vital_replay_corpus


class VitalReplayCorpusTests(unittest.TestCase):
    def setUp(self) -> None:
        self.temporary_directory = tempfile.TemporaryDirectory()
        self.root = Path(self.temporary_directory.name).resolve()
        self.contract_root = Path(__file__).resolve().parents[2]
        self.corpus_directory = self.root / "corpus"
        self.corpus_directory.mkdir()
        self.sources = {
            version: self.corpus_directory
            / ("approved-recorder-v" + str(version) + ".vital")
            for version in (1, 2, 3)
        }
        for version, source in self.sources.items():
            source.write_bytes(
                ("nonclinical-recorder-vital-v" + str(version)).encode("ascii")
            )
        self.source = self.sources[1]
        self.manifest = self.root / "manifest.v1.json"
        document = json.loads(
            (
                self.contract_root
                / "contracts"
                / "examples"
                / "v1"
                / "valid"
                / "vital-replay-corpus-manifest.json"
            ).read_text(encoding="utf-8")
        )
        for entry in document["entries"]:
            source = self.sources[entry["formatVersion"]]
            entry["byteSize"] = source.stat().st_size
            entry["sha256"] = hashlib.sha256(source.read_bytes()).hexdigest()
        self.manifest.write_text(
            json.dumps(document),
            encoding="utf-8",
        )

    def tearDown(self) -> None:
        self.temporary_directory.cleanup()

    def verify(self) -> vital_replay_corpus.VerifiedVitalReplayCorpus:
        return vital_replay_corpus.verify_vital_replay_corpus(
            self.contract_root,
            self.manifest,
            self.corpus_directory,
        )

    def test_verifies_exact_human_approved_registered_bytes(self) -> None:
        corpus = self.verify()
        self.assertEqual("approved-vital-replay-corpus-1", corpus.corpus_id)
        self.assertEqual(3, len(corpus.entries))
        self.assertEqual(self.source, corpus.entries[0].path)

    def test_rejects_digest_mismatch(self) -> None:
        self.source.write_bytes(b"different")
        with self.assertRaisesRegex(
            vital_replay_corpus.VitalReplayCorpusError,
            "byte size mismatch|SHA-256 mismatch",
        ):
            self.verify()

    def test_rejects_unregistered_vital_file(self) -> None:
        (self.corpus_directory / "unreviewed.vital").write_bytes(b"unknown")
        with self.assertRaisesRegex(
            vital_replay_corpus.VitalReplayCorpusError,
            "unregistered=unreviewed.vital",
        ):
            self.verify()

    def test_rejects_symlinked_corpus_entry(self) -> None:
        target = self.root / "outside.vital"
        target.write_bytes(self.source.read_bytes())
        self.source.unlink()
        self.source.symlink_to(target)
        with self.assertRaisesRegex(
            vital_replay_corpus.VitalReplayCorpusError,
            "non-symlink regular file",
        ):
            self.verify()


if __name__ == "__main__":
    unittest.main()
