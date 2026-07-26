# Stale guest-tools rootfs cache in clean install

## Symptom

A freshly installed Helper can show behavior that was already fixed in source,
for example:

```text
Guest product services probes: docker stats ... timed out
```

The same fix may appear to work only after applying a Product Update bundle.

## Cause

The development PKG reuses the golden rootfs cache only when the rootfs
contract fingerprint and material receipt are unchanged. The fingerprint
previously listed only a small subset of guest-tools files. Changes in modules
such as the Guest Control API compose adapter did not necessarily invalidate
the rootfs cache, so a clean install artifact could embed an older guest-tools
environment.

There was a second, independent cache error: a cache miss could start
cloud-init on the prior golden `vm-disk.img` when `VM_RECREATE_ROOTFS=false`.
That is neither cache reuse nor a clean compile. A changed config or rootfs
size could therefore inherit package/database/filesystem state from an older
compile even though the rootfs archive itself was regenerated.

This is a packaging contract failure. A clean install artifact must not require
a follow-up Product Update to receive source changes that are part of the same
release candidate.

## Fix Direction

The golden rootfs contract fingerprint must include the full Guest support
payload and the full `packages/vitalserver-guest-tools/src` tree. It must also
bind the effective build config and rootfs size. After changing guest-tools
behavior, rebuild the PKG with a regenerated golden rootfs when the previous
cache may have been created before this dependency fix.

The rebuild rule is explicit: receipt and fingerprint both match means reuse;
every other outcome means delete/recreate the golden root disk before cloud-init
and rootfs smoke begin. Cache invalidation must never mean "continue the old
golden disk".

## Prevention

Treat golden rootfs cache reuse as a product compile decision. Cache inputs must
cover every file and effective setting that can change guest runtime behavior,
and a non-reusable cache must always start from a fresh base disk. Do not rely
on update bundle application to repair a newly built install package.
