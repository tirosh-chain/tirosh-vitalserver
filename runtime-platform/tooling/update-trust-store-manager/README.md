# Update publisher trust manager

`update-trust-store-manager` is release tooling for the public keys that Hosts
use to verify signed Update Bootstrap Envelopes. It never accepts a private
signing key.

Every command writes a new immutable directory containing:

- `update-trust-store.json`: the Host Update Trust Store packaged into every
  Host release;
- `transition-receipt.json`: the
  `UpdatePublisherTrustTransitionReceipt` that binds the source and result
  trust-store digests plus added, removed, and retained key IDs.

The output directory must not already exist.

## Provision the first trust anchor

```sh
update-trust-store-manager \
  --action provision \
  --transition-id publisher-trust-provision-2026 \
  --key-id vitalserver-release-key-2026 \
  --public-key /release/keys/vitalserver-release-key-2026.public.base64 \
  --transitioned-at 2026-07-27T00:00:00Z \
  --output-directory /release/trust/provision-2026
```

Provision has an explicitly absent source store. Supplying a source or an
expected source digest is rejected.

## Rotate with an overlap release

```sh
update-trust-store-manager \
  --action rotate \
  --transition-id publisher-trust-rotation-2027 \
  --source-trust-store /release/trust/provision-2026/update-trust-store.json \
  --expected-source-sha256 <reviewed-source-sha256> \
  --key-id vitalserver-release-key-2027 \
  --public-key /release/keys/vitalserver-release-key-2027.public.base64 \
  --transitioned-at 2027-01-01T00:00:00Z \
  --output-directory /release/trust/rotation-2027
```

Rotation adds one distinct key and retains every old key. Release order is:

1. ship the overlap trust store in a bundle signed by an already trusted key;
2. verify that the overlap release is installed;
3. begin signing later bundles with the new key.

## Revoke only after new-key adoption

```sh
update-trust-store-manager \
  --action revoke \
  --transition-id publisher-trust-revocation-2026 \
  --source-trust-store /release/trust/rotation-2027/update-trust-store.json \
  --expected-source-sha256 <reviewed-overlap-sha256> \
  --key-id vitalserver-release-key-2026 \
  --transitioned-at 2027-02-01T00:00:00Z \
  --output-directory /release/trust/revocation-2026
```

Revocation removes exactly one key and refuses to produce a store with no
remaining trusted key. The revocation release must be signed by a retained
key. A Host with the resulting store rejects a bundle signed by the removed
key as `update-bootstrap-signature-invalid`; there is no legacy verifier
fallback.

`release-composer --trust-store` independently derives the public key from the
selected private signing key and requires an exact key-ID/public-key match in
the selected store before it emits a signed bundle.
