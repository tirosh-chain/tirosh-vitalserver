# Stale guest-tools rootfs cache in clean install

## Symptom

A freshly installed Helper can show behavior that was already fixed in source,
for example:

```text
Guest product services probes: docker stats ... timed out
```

The same fix may appear to work only after applying a Product Update bundle.

## Cause

The development PKG reuses the golden rootfs cache when the rootfs contract
fingerprint is unchanged. The fingerprint previously listed only a small subset
of guest-tools files. Changes in modules such as the Guest Control API compose
adapter did not necessarily invalidate the rootfs cache, so a clean install
artifact could embed an older guest-tools environment.

This is a packaging contract failure. A clean install artifact must not require
a follow-up Product Update to receive source changes that are part of the same
release candidate.

## Fix Direction

The golden rootfs contract fingerprint must include the full Guest support
payload and the full `packages/vitalserver-guest-tools/src` tree. After changing
guest-tools behavior, rebuild the PKG with a regenerated golden rootfs when the
previous cache may have been created before this dependency fix.

## Prevention

Treat golden rootfs cache reuse as a product compile decision. Cache inputs must
cover every file that can change guest runtime behavior. Do not rely on update
bundle application to repair a newly built install package.
