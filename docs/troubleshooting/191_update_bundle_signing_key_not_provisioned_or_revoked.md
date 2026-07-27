# Update bundle signing key is not provisioned or was revoked

- **ID:** TS-191
- **Category:** Update / Packaging
- **Owner:** Release process
- **Status:** active

## Symptom

Release composition stops before publishing a bundle because the selected
private signing key does not match the public key under its declared key ID in
the Host Update Trust Store. Alternatively, a Host rejects an older bundle
with `update-bootstrap-signature-invalid` and reports that its trust store has
no matching key ID.

## Cause

Publisher authenticity is owned by the packaged public trust store, not by a
successful SHA-256 integrity check and not by the availability of a private
key on a build machine.

The usual causes are:

- the release process selected a private key before provisioning its public
  key into the store shipped to Hosts;
- a key ID was paired with different public/private bytes;
- rotation skipped the overlap release and started signing with the new key
  too early;
- revocation removed the old key before all supported installations adopted
  the new key;
- the source trust-store bytes changed after review.

## Fix direction

Use `update-trust-store-manager` for a digest-fenced transition:

1. provision the initial public key;
2. rotate by adding the new key while retaining the old key;
3. ship and observe the overlap release;
4. sign subsequent releases with the new key;
5. revoke the old key in a later release signed by the retained key.

Do not restore an old key implicitly, bypass `release-composer --trust-store`,
or treat checksum success as publisher trust.

## Prevention principle

Signing authority and Host verification authority must agree before bundle
publication. Every trust change creates a new immutable store and an
`UpdatePublisherTrustTransitionReceipt`; private signing material never enters
that receipt or a product package.

## Verification

```sh
make -C runtime-platform update-trust-store-manager-test
make -C runtime-platform release-composer-test
make -C runtime-platform installation-update-acceptance
```

## Related cases

- [TS-188](188_update_bundle_integrity_mistaken_for_publisher_trust.md)
