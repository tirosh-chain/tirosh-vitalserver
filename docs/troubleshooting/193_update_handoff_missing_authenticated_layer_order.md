# Update handoff invocation cannot prove the authenticated layer order

## Symptom

- The installed Host verifies an Update Bootstrap Envelope and starts the
  bundle-owned next updater.
- The handoff invocation identifies the envelope and specification digest, but
  does not contain the envelope's authenticated layer order.
- A next updater can decode the Product Update Specification, but cannot prove
  that its layer plan preserves the order approved by the installed Host.

## Cause

The initial Helper handoff contract carried correlation identities, digests,
artifact paths, and the expected journal revision, but omitted `layerOrder`.
The Host still owned the authenticated order in its journal. That state was not
provided explicitly to the next updater boundary.

Reading the detailed specification alone is not a substitute. The
specification is intentionally owned by the bundle's next updater and may
evolve. Letting it provide both the desired steps and the safety order would
remove the stable bootstrap constraint, including the rule that Host Platform
replacement must run last.

## Fix direction

1. Include the exact bootstrap-envelope `layerOrder` in
   `UpdateBootstrapHandoffInvocation`.
2. Strictly decode the bundle-owned Product Update Specification.
3. Pass both documents as complete input to a pure execution planner.
4. Require exact layer coverage and order without sorting.
5. Require every dependency to refer to a preceding layer.
6. Reject Host Platform unless it is the final layer.
7. Validate immutable artifact, executor, configuration, and rollback
   identities before any effect is invoked.

Do not recover the order from logs, filenames, executor names, or a default
Container → Guest Runtime → Host Platform list.

## Prevention

When one owner authenticates a safety constraint and another component executes
the operation, the handoff contract must carry that constraint explicitly.
Digest correlation proves which specification bytes were selected; it does not
by itself provide the stable policy inputs needed to validate those bytes.

The next updater may extend its detailed specification, but it must not replace
or infer the Host-authenticated layer order.
