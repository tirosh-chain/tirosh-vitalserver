# Reference Fixtures

This quarantined directory holds small, sanitized observations from the existing product. It is a behavior reference during the replacement, not a source dependency and not a second implementation root.

Fixtures are data only. New production code must never import or execute them. Only the acceptance harness may read a fixture, and it must map the captured fact to an explicit new-platform contract.

## What a fixture may prove

A fixture can prove a narrow observed fact, such as:

- the legacy Recorder uses the `join_vr` and `send_data` Socket.IO event shapes;
- a durable-spool success and a spool-full rejection were distinct outcomes;
- a legacy Vital-file library upload used multipart `files` input and could return a partial per-file result.

It must not dictate a new domain meaning. In particular, the legacy Vital-file library upload result is **not** an `ExportReceipt` success. C6 requires source finalization, immutable manifest, upload, and indexing facts before `outcome: succeeded` is possible.

## Safety and provenance contract

Every registered fixture is listed in [manifest.v1.json](manifest.v1.json). The manifest records:

- the source repository revision, source path, capture date, and a human-reviewable test locator;
- a SHA-256 digest of the sanitized fixture bytes;
- explicit evidence that raw protocol content, patient data, network addresses, and secret material were removed;
- the C1–C6 contract the acceptance harness may use it to exercise.

The verifier rejects unregistered JSON fixtures, digest mismatches, path escapes, incomplete provenance, and prohibited raw-data keys. It does not claim that an automated key scan can prove a recording is safe; a human reviewer must inspect every fixture before it is registered.

## Capture and review workflow

1. Read a behavior source at a fixed legacy commit. Do not copy a source file or raw recording into this directory.
2. Reduce it to the smallest structural fact required by a future protocol spike or acceptance test. Replace identifiers and omit payload bytes, filenames, endpoints, patient information, and credentials.
3. Add the JSON fixture and calculate its digest:

   ```sh
   python3 -c 'from pathlib import Path; import hashlib; p = Path("runtime-platform/acceptance/reference-fixtures/recorder-socketio/join-vr.json"); print(hashlib.sha256(p.read_bytes()).hexdigest())'
   ```

4. Register the source revision, locator, sanitization assertions, digest, and C1–C6 mapping in `manifest.v1.json`.
5. Run the integrity checks:

   ```sh
   make -C runtime-platform reference-fixture-check
   make -C runtime-platform test-reference-fixtures
   ```

No capture command may traverse into the parent legacy source tree. That boundary makes a fixture update a deliberate, reviewed translation rather than a hidden runtime dependency.
