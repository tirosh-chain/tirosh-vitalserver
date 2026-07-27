# Product update composition

This directory declares product-level update composition, not an updater
implementation. The canonical transport/state contracts are C25–C31 in
`contracts/`; Host Agent and `host-updater` remain the executable owners.

Every release must carry these distinct inputs:

1. A small immutable C25 `UpdateBootstrapEnvelope`, signed with the release
   trust key. It names the platform, ordered layers, next-updater artifact, and
   the opaque C26 specification artifact digest.
2. A signed next-updater artifact. The currently installed Host updater stages
   this artifact after verifying C25. It does **not** parse C26.
3. The evolving C26 `ProductUpdateSpecification`, parsed only by that staged
   next updater.
4. Layer artifacts, explicit rollback declarations, and one distinct
   digest-verified `effectExecutor` per layer. The executor accepts only the
   fixed C55 apply/rollback protocol and records a typed receipt. It is a
   release-owned product-composition responsibility, not a Host Agent domain
   fallback.

For the Guest Runtime layer, the release-owned
`guest-product-release-effect-executor` is the C55 executable. Its C61
configuration names the one C32 Host-loopback bridge to C59 and the exact
compare-and-swap release transition for apply (and, when declared, rollback).
It checks the Host-staged archive again, streams that archive with the C59
command, and writes a correlated C55 receipt. A missing configuration, a
changed archive, an unavailable bridge, an invalid C59 response, and a
non-terminal release operation stay distinct receipt outcomes; none becomes a
guessed Guest release or a successful update.

`tooling/release-composer` owns deterministic release assembly. Given an
explicit `ReleaseBundleComposition`, a payload directory, and an Ed25519
release key, it produces one new bundle directory containing the complete
`payload/` tree, the signed C25 `bootstrap-envelope.json`, and a deterministic
`bundle-content-manifest.json`. It calculates artifact size and SHA-256 from
payload bytes; it does not trust caller-supplied integrity values. Reusing an
existing output directory is rejected rather than silently replacing a bundle.

For the current macOS arm64 Product update path,
`tooling/product-update-composer` prepares that generic payload. It consumes
one release-process-only source selection document and composes the selected
Container, Guest Runtime, and Host Platform transitions in that order. It
copies the next updater, selected archives, and each layer effect executor as
regular immutable payload files, generates the layer-specific configurations
and Product Update Specification from their resulting digests, then emits the
`ReleaseBundleComposition` consumed by the generic signer. Source filesystem
paths do not enter deployed contracts.

`tooling/guest-product-release-archive-composer` is the preceding release
artifact step. It turns a selected release tree into the exact tar+gzip media
type C59 accepts, preserving only C59-safe relative links. The archive's
resulting bytes, digest, and size—not its source tree—are what C26 carries.

The Host's `StagedBundleBootstrapper` resolves `bundleReferenceId` beneath its
configured `UpdateBundleStore`, verifies C25 and its two known artifacts, then
copies the whole payload into Host-owned staging. Only after C29 is durably
`handoff-pending` does it atomically create C30 inside that staged directory.
C30 points the next updater to C26 without making the current Host parse C26,
and fixes the original `requestId` plus exact
`expectedHandoffJournalRevision` required by C27 completion. The Host
atomically verifies that handoff revision, enters `applying`, and settles C28.
C31 is the separate durable queue item that
names the original C30 path relative to Host staging. This distinction
preserves C30's payload-path base directory. A stage, C30, and its C31 handoff
are each atomically published and idempotent in their own owner boundary.

Before C27, C69 provides the operator-facing offline intake boundary.
`HostUpdateBundleImportCommand` carries one OS-authorized, Host-local release
bundle directory. The Host Bundle Store decodes only the shape of C25,
rejects symlinks, special files, partial trees, and same-ID/different-byte
conflicts, then atomically copies one complete immutable tree into its private
store. An import receipt's `bundle.state=declared` is deliberately not
signature verification: C27's `StagedBundleBootstrapper` remains the only C25
trust decision. `HostUpdateBundleApplyCommand` carries the current C7 identity
and revision plus the imported ID; the Host rereads C25 from its own store and
creates C27 internally. Desktop Console and `platformctl` therefore never
construct C25, select payload paths for C27, or treat an imported directory as
an update success result.

`host-update-handoff-supervisor` is the C31 consumer. Its C56 deployment
configuration names the queue, staging root, C28/C55 evidence roots, C52
descriptor, bounded timeouts, and its service poll interval explicitly. For a
selected C31 it verifies
the original C30 and only the C25-selected next-updater bytes; it does not
decode C26. It invokes the updater with fixed arguments and publishes an
immutable C57 receipt. C57 `completion-submitted` means the updater returned a
correlated C27 after C52 accepted it; it is not a product-update success claim.
C29 remains the sole Host settlement state. A missing, stale, invalid C31,
C30, C25, updater byte, C52 descriptor, or process result becomes an explicit
C57 failed/unavailable receipt rather than a guessed retry success. The
OS-managed supervisor runs its distinct service mode and revisits only the
declared queue at that C56 interval. Its stable C57 attempt ID means a
retained failed/unavailable receipt is not redispatched merely because the
service polls or restarts.

The staged `host-updater` verifies every declared layer artifact, rollback
artifact, and effect-executor byte before invoking the executor directly (no
shell expression or C26-defined argument list). It accepts only a correlated
C55 receipt as the semantic effect outcome, produces C28 atomically, and
returns C27 to the exact Host Agent C52 OS-local transport. A process exit,
log line, missing receipt, or different existing C28 report is explicit
failure/unavailability, never a fallback success.

## C24 transition evidence is a second, OS-observed fact

`tooling/host_platform_release_transition_evidence.py` is the release-process
correlation verifier for a future clean-Host `update` or `rollback` evidence
run. It reads immutable copies of C29, C28, and the C55 Host-platform effect
receipt, binds their exact bytes, and rejects a target platform/version,
update ID, C28 layer evidence, or C55 receipt that does not correlate. Before
reading those correlations it validates the raw C29 journal and C55 receipt
against their published schemas; it also validates the selected current C48
manifest and a fresh native C49 footprint. The C49 must prove the C48 package
receipt, immutable slot, activation target, all declared service definitions,
declared transaction paths, and completed C50 transaction. Partial JSON that
merely contains matching field names is not release evidence.

For an `update`, it requires succeeded C29/C28 and a succeeded
`host-platform` C55 **apply** receipt with the same C28 evidence reference.
Its observed C48 product version must equal the selected C23 target version.
For a `rollback`, it requires failed C29/C28, C28
`rollback.state=succeeded`, and a separate succeeded Host-platform C55
**rollback** receipt; the C48/C49 pair records the actual restored release,
which may predate the attempted target version. The emitted document is still
not C24 success: the matching OS clean-Host runner must independently verify
the physical Host and bind this immutable evidence. C68 changes the active
immutable slot; an MSI/DEB/PKG receipt cannot stand in for that fact.

The verifier has no command that starts an update, switches a release, or
edits `release-delivery-proofs.v1.json`. C29, C28, C55, C68, OS package
managers, and C24 each retain their own owner and meaning.

There is no `minimumUpdaterVersion` contract. Compatibility is held at the
small C25 boundary: if its schema, signature, artifact, or trust evidence
cannot be verified, the Host returns a typed failed/unavailable bootstrap
receipt and does not attempt an old-spec parser or another update path.

## Publisher trust lifecycle

The Host package contains only the public C58 Host Update Trust Store.
`tooling/update-trust-store-manager` is the release-process owner for initial
provisioning, overlap rotation, and revocation. It emits a C83
`UpdatePublisherTrustTransitionReceipt` binding the exact input/output store
digests and affected key IDs; private keys are not valid input to that
boundary.

Rotation is deliberately two release-process transitions, not an updater
bridge. First, a release signed by an already trusted key installs an overlap
store containing both old and new public keys. After that release is observed,
later bundles may use the new signing key. A subsequent bundle signed by the
new key may install a store with the old key removed. Removing the final key,
reusing a key ID for different bytes, changing the reviewed source store, or
signing with a private key that does not match the selected packaged public
key is rejected before bundle publication.

## Installed product baseline

Runtime Platform is a clean-install product root, not an in-place extension of
the legacy macOS Helper. Its installed update baseline contains the Host
Agent's stable envelope verifier and journal, the Update Handoff Supervisor,
the public Host Update Trust Store, and the Runtime Console import/apply
interface. The installed baseline deliberately does not contain a current
`host-updater` executable: every signed release bundle supplies the exact next
updater that owns that bundle's Product Update Specification.

The legacy Helper's `minUpdaterVersion` and `requiresTwoPhaseUpdate` policy
remains outside this product root as historical product code. Runtime Platform
does not call it, package it, or migrate its update state. The independent-root
boundary check rejects either legacy gate if it is introduced into Runtime
Platform production code or configuration. A future Helper-to-Runtime-Platform
transition, if required, is a separately specified migration and must not
become a fallback update path.

`../delivery/support-matrix.v1.json` names macOS arm64 as the first planned
clean-install target and records Windows/Linux as planned consumers of the
same C25–C31 contracts. `planned` is not an install, package, or clean-host
proof; C24 remains the release-proof authority.
