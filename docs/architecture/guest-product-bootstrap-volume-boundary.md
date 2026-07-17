# Guest Product Bootstrap Volume Boundary

## Purpose

Guest Product binaries, configuration, Recorder Gateway archive, and systemd
unit must reach a newly booted Guest without granting a Host release build the
authority to edit the Guest-owned root filesystem. C40 therefore means a
**read-only delivery artifact**, not a Host-side ext4 edit request.

`GuestProductBootstrapVolumeCompositionPlan` declares exactly what will be
delivered. `GuestProductBootstrapVolumeComposer` verifies the declared source
bytes and produces one immutable RAW storage image. Its Guest-visible MBR
partition contains the NoCloud ISO9660 filesystem labeled `CIDATA`. Guest
cloud-init later owns the installation into the Guest root filesystem.

## Ownership and vocabulary

| Name | Owner | Responsibility |
| --- | --- | --- |
| C37 `GuestProductProcessDeploymentConfiguration` | Guest Product release author | desired process executable and configuration paths |
| C38 `GuestProductServiceManagerDeploymentConfiguration` | Guest Product release author | declared systemd unit name, supervisor invocation, restart/install policy |
| C39 `GuestProductBootstrapConfiguration` | Guest Product release author | bootstrap identity, Guest payload destinations, archive and service-link intent |
| C40 `GuestProductBootstrapVolumeCompositionPlan` | Guest Product bootstrap release composer | complete, byte-pinned request that names `storageImageFormat=raw` and `guestVolumeFileSystem=iso9660` separately |
| `NoCloudGuestProductBootstrapVolumeAdapter` | selected release-build effect adapter | creates one RAW image with a `CIDATA` ISO9660 partition; never mounts or edits a Guest root |
| cloud-init bootstrap script | Guest | verifies payload bytes, installs/extracts/link/enables the declared product service |
| `/var/lib/vitalserver/bootstrap-completed` | Guest | completion fact written only after every declared Guest-owned step succeeds |

`serviceUnitName` is intentionally a C40 field. It cannot be hidden in the
composer as `vitalserver-guest-product.service`, because C38 is the owner of
the selected systemd service vocabulary. The plan also names all source bytes,
Guest paths, modes, archive entry-mode policy, archive symbolic-link policy,
required archive paths, and enabled-unit link. Missing, unreadable, wrong-size,
wrong-digest, or unsafe inputs fail composition; they do not produce an empty
volume.

`entryModePolicy=preserve-archive-mode` answers only whether the declared tar
entry modes survive extraction. It does not imply that arbitrary tar links are
safe. `symbolicLinkPolicy=allow-relative-links-to-declared-regular-files`
separately authorizes the Node.js package-manager links used by Recorder
Gateway: C40 accepts a link only when its relative target resolves inside the
same archive and names a declared regular-file entry. Absolute links,
archive-root escapes, directory links, link chains, hard links, device nodes,
and other tar entry types remain rejected before C40 publishes a bootstrap
volume.

C40 does **not** define product completeness as a historical count such as
“seven sources” or “six files.” C39 and the C37/C38/C44/C46 composition rules
own which product roles must be present for a selected topology. C40 instead
enforces the invariant it owns: each named bootstrap payload has exactly one
declared file or archive installation, and the one service enable link targets
the installed file whose basename is the C38-declared `serviceUnitName`.
Therefore an added, removed, or optional product payload cannot accidentally
be accepted or rejected merely because an old list length happened to change.

## One-directional flow

```text
C37 process deployment + C38 service deployment + C39 bootstrap configuration
                    + byte-identified release payloads
                                      |
                                      v
              C40 GuestProductBootstrapVolumeCompositionPlan
                                      |
                                      v
         NoCloudGuestProductBootstrapVolumeAdapter (Host release build)
                                      |
                                      v
      read-only RAW storage image → ISO9660 partition, label CIDATA
                                      |
                                      v
             Guest cloud-init bootstrap script (Guest-owned effect)
                                      |
                                      v
 Guest files + Recorder Gateway archive + systemd unit/link + completion fact
```

The Host's success means only that the volume was composed from verified input
bytes. It does **not** mean cloud-init recognized the ISO, the Guest booted,
the service started, the Guest Runtime became ready, or a Host package was
installed. Those are later observations and need their own receipts/evidence.

## Why the previous raw-root editor is removed

The previous C40 design called a `GuestRootFilesystemEditor` from the Host
release build. It failed on a real Ubuntu Noble ext4 extent tree, but the more
important issue is the ownership boundary: the Host had authority to mutate
Guest root bytes and had to understand Guest filesystem implementation details.
That violates the product rule that the Guest owns filesystem and product
process state.

NoCloud moves the boundary to an explicit, portable transport artifact. The
Host chooses neither a Guest partition nor an ext4 implementation. The Guest
accepts a named `CIDATA` volume, verifies exact bytes, and performs its own
filesystem and systemd effects. C43 still owns the raw root-storage base;
after the migration it no longer feeds a Host ext4 editor.

## Current executable scope

`runtime-platform/tooling/guest-product-bootstrap-volume-composer/` contains
the C40 plan validation, source/archive identity verification, RAW storage
image plus ISO9660 partition composition, and focused tests for the generated
Guest bootstrap program. Its
`GuestProductBootstrapArtifactComposer` command is the selected C35 builder:
it preserves the C43 root bytes, copies declared boot artifacts, and composes
the second C35 storage artifact. C41, C35, C34, and C32 now carry the exact
two-storage contract: writable RAW `guest-root` followed by a read-only RAW
`guest-product-bootstrap` image whose Guest filesystem is ISO9660. Both
commands build for macOS ARM64, Linux ARM64, and Windows AMD64.

The remaining work is first-Guest-boot evidence: attach the two declared
artifacts to an actual Guest, prove cloud-init accepts `CIDATA`, and then prove
the declared service and package lifecycle. Until that evidence exists, this
document does not claim a bootable or installable release.
