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
4. Layer artifacts and explicit rollback declarations. Their effect adapters
   are selected product-composition responsibilities, not a Host Agent domain
   fallback.

`tooling/release-composer` owns deterministic release assembly. Given an
explicit `ReleaseBundleComposition`, a payload directory, and an Ed25519
release key, it produces one new bundle directory containing the complete
`payload/` tree, the signed C25 `bootstrap-envelope.json`, and a deterministic
`bundle-content-manifest.json`. It calculates artifact size and SHA-256 from
payload bytes; it does not trust caller-supplied integrity values. Reusing an
existing output directory is rejected rather than silently replacing a bundle.

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

There is no `minimumUpdaterVersion` contract. Compatibility is held at the
small C25 boundary: if its schema, signature, artifact, or trust evidence
cannot be verified, the Host returns a typed failed/unavailable bootstrap
receipt and does not attempt an old-spec parser or another update path.

`../delivery/support-matrix.v1.json` names macOS arm64 as the first planned
clean-install target and records Windows/Linux as planned consumers of the
same C25–C31 contracts. `planned` is not an install, package, or clean-host
proof; C24 remains the release-proof authority.
