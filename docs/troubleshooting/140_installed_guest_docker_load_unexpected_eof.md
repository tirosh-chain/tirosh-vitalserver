# Installed Guest Docker load ends with unexpected EOF

> ID: TS-140
> Category: Guest bootstrap / Guest containers / Packaging
> Owner: Guest bootstrap and package activation
> Status: active

## Symptoms

The PKG receipt, VM process, Host services, and Guest Control health endpoint are
available, but the VM remains `Starting`. The bootstrap log shows several
`Loaded image` lines followed by:

```text
unexpected EOF
docker load -i /mnt/tirosh/deploy/docker-images/vitalserver-images.tar.gz
returned non-zero exit status 1
```

Compose is only partially created and `bootstrap-result.json` does not report a
completed bootstrap.

## Cause

`docker load` can fail after a partial import even when the Host bundle has the
same size and SHA-256 as the compiler input and the same bundle passed the
golden Guest load proof. The old bootstrap performed one import attempt, so a
single external command failure left the fresh runtime unable to converge.
Package reinstall also preserved the previous cloud-init seed, so replacing the
Guest deploy payload did not activate bootstrap again in an existing VM.

An archive with a different digest, a missing referenced blob, or a failed
compiler verifier remains a bundle compile failure covered by TS-117. It must
not be reclassified as this retryable execution case.

## Fix Direction

Guest bootstrap performs at most three explicit, idempotent attempts for the
same Docker bundle. Every failed attempt reports the attempt count, exit code,
and bundle path. Exhausting the attempts preserves the command failure and
prevents Compose startup.

Package reinstall preserves `vm-disk.img`, `runtime-data.img`, Host settings,
Vital files, and backups, but refreshes the cloud-init seed with a new instance
ID so the newly installed Guest deploy bootstrap is actually executed.

Docker Compose health omitted by Docker is mapped at the Docker adapter
boundary to the explicit `not_reported` state. SQLite decoding remains strict.

## Prevention

- Bind field-delivery proof to the current rootfs, Guest deploy material, and
  Docker bundle identities.
- Do not install an artifact merely because the PKG/DMG file appeared; the
  complete `make dist/dmg/dev` runtime-smoke gate must finish successfully.
- Keep image-load retries bounded and observable. Never interpret exhausted
  attempts or partially loaded images as success.
- Reinstall activation artifacts must execute the newly delivered bootstrap
  without replacing mutable runtime data.

## Related Cases

- `TS-117`: Docker multi-platform export omitted Guest blobs.
- `TS-139`: PKG fresh/reinstall transition and data-preserving cleanup.

## Follow-up

- 2026-07-15: added bounded Docker load attempts, explicit unreported health
  mapping, and cloud-init seed refresh during package provisioning.
