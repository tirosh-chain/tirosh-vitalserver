# GuestArtifactCompiler

`guest_artifact_compiler.py` is the C35 **release-build orchestrator**. Its
name deliberately says what it owns: it verifies an already-complete Guest
artifact compilation command and publishes compiler evidence. It is not a
Linux image editor, a cloud-init implementation, or a VM lifecycle controller.

## Contract vocabulary

| Contract / executable | Role |
| --- | --- |
| C41 `GuestArtifactCompilationInputAssemblyDeclaration` | selects named build-machine sources and the selected composer |
| C35 `GuestArtifactCompilationCommand` | identity-pins all input bytes and the expected artifact roles |
| `GuestProductBootstrapArtifactComposer` | selected C35 executable; copies the root base and composes `CIDATA` |
| C40 `GuestProductBootstrapVolumeCompositionPlan` | derived request for the NoCloud volume |
| C34 `MacOSGuestArtifactManifest` | role/storage-image-format/Guest-filesystem/digest identity of C35 outputs |
| C35 `GuestArtifactCompilationReceipt` | C35 command, selected-composer, input, and C34 correlation |

## Explicit invocation

```sh
python3 runtime-platform/tooling/guest_artifact_compiler.py \
  --compilation-command /absolute/C35.json \
  --input-root /absolute/c35-input \
  --builder-executable /absolute/guest-product-bootstrap-artifact-composer \
  --output-directory /absolute/new-output \
  --builder-timeout-seconds 600
```

The output directory must not already exist. The compiler creates a private
temporary directory, executes only the byte-identified composer, validates the
declared output set, writes C34 and a C35 receipt, then atomically publishes
the directory. Failure removes that temporary directory and reports the C35
`compilationId`, stage, and bounded composer diagnostic.

`completedAt` in the C35 receipt is recorded by `GuestArtifactCompiler` after
the selected builder and C34 output validation succeed. It is not a CLI input:
the caller selects source, builder, output destination, and timeout, but cannot
pre-claim the completion time of this compiler effect.

## Required output set

The C35 command declares exactly:

- `boot/Image` (the C42-decompressed ARM64 Linux boot-loader kernel), and optional `boot/initrd.img`;
- `storage/guest-root.raw` — `guest-root-storage`, a writable RAW storage
  image; and
- `storage/guest-product-bootstrap.raw` —
  `guest-product-bootstrap-volume`, a read-only RAW storage image whose
  Guest-visible partition contains the ISO9660 `CIDATA` filesystem.

The selected composer must never write an undeclared file. It copies the
declared root base but never opens it as a filesystem. It derives C40 from
C37/C38/C39/C44 and, only for an external C44 topology, C46; it produces the
RAW bootstrap disk through the named NoCloud adapter. The later
Guest cloud-init program owns root filesystem and systemd effects.

Neither a successful invocation nor C34/C35 receipt proves Guest boot,
cloud-init completion, Recorder delivery, package installation, or C24 clean
Host evidence. See [Guest Artifact Build Boundary](../../docs/architecture/guest-artifact-build-boundary.md).
