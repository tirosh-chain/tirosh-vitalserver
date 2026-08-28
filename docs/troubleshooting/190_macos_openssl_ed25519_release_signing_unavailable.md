# macOS OpenSSL cannot create an Ed25519 update signing key

> ID: TS-190
> Category: Packaging / Update / Local development
> Owner: update release publisher tooling
> Status: resolved

## Symptoms

Building the Helper 0.2.2 stable update bootstrap bundle fails before an
envelope is signed. A direct signing probe can report:

```text
openssl genpkey -algorithm ED25519
Algorithm ED25519 not found
```

The updater, specification, and output directory may all exist. This is not
evidence that the release bundle or publisher key is invalid.

## Impact

The release publisher cannot produce an authenticated bootstrap closure on the
affected machine. No update should be published from unsigned bytes, and the
failure must not be converted into an integrity-only success.

## Cause

The `/usr/bin/openssl` available on some macOS installations is LibreSSL and
does not provide the same Ed25519 command-line capabilities as current OpenSSL.
Treating a host `openssl` executable as a portable signing contract therefore
makes release behavior depend on the build machine.

## Checks

```sh
/usr/bin/openssl version
/usr/bin/openssl genpkey -algorithm ED25519
.venv/bin/python -c 'from cryptography.hazmat.primitives.asymmetric.ed25519 import Ed25519PrivateKey; print(Ed25519PrivateKey.generate())'
```

The first two commands diagnose the host executable only. The final command
checks the signer implementation used by `vitalserver-devtools`.

## Actions

Use the repository-managed release commands:

```sh
.venv/bin/vitalserver-devtools update-bootstrap-bundle --help
.venv/bin/vitalserver-devtools verify-update-bootstrap-bundle --help
```

Provide an explicit unencrypted Ed25519 PKCS#8 PEM private key when building and
the corresponding Ed25519 SubjectPublicKeyInfo PEM public key when verifying.
Do not copy a private key into the repository or release archive.

## Prevention

Stable update signing and verification use the Python `cryptography` Ed25519
API on macOS, Windows, and Linux. Release tooling does not discover or invoke a
host OpenSSL implementation. Tests verify the exact Swift canonical payload,
publisher signature, bound artifact bytes, exact file closure, and rejection
of symlinks.

## Operational Notes

The publisher key ID in the envelope must identify a public key already
admitted by the installed Host trust-store contract. Successful local signing
alone does not admit a new trust root.

## Related Cases

- `TS-188`: integrity verification is not publisher authentication.

## Follow-up

- 2026-07-27: Stable bootstrap bundle composition moved to the repository
  `cryptography` dependency and cross-platform Ed25519 tests.
