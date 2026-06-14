# Upstream VitalServer Contract Verification Failure

## Symptom

`make repo/verify-submodule`, `make dist/pkg/dev/verify`, or `make dist/dmg/dev/verify` fails before
package or DMG compile with output like:

```text
failed: required upstream contract pattern is missing
stage: required-contract
rule: redis.vrcode_ip.write
file: vitalserver-old/service/app.js
```

or:

```text
failed: forbidden upstream patch marker is present
stage: forbidden-marker
rule: upstream.proxy_header_ip_patch
```

## Cause

The Helper runtime depends on a small explicit contract from the original `vitaldb/vitalserver`
submodule. VitalServer must still expose the expected Socket.IO lifecycle and Redis `ip_<vrcode>`
read/write behavior, and VRecorder IP correction must remain owned by the audit proxy.

The verification fails when one of these meanings changes:

- `.gitmodules` no longer points at `https://github.com/vitaldb/vitalserver.git`.
- `vendor/vitalserver` is dirty or unreadable.
- The pinned commit is not in `config/upstream-vitalserver-contract.json` `approvedCommits` during
  release verification.
- Required files such as `vitalserver-old/service/app.js` are missing.
- Required `join_vr`, `join_bed`, `send_data`, `recv_vr_ipaddr`, or Redis `ip_` behavior is not visible.
- Fork-style proxy header IP patch markers such as `x-forwarded-for`, `VITALSERVER_TRUST_PROXY`, or
  `get_vr_client_ip` are present in upstream code.

## Fix Direction

If the submodule was changed unintentionally, pin it back to an approved commit and rerun:

```sh
make repo/verify-submodule
```

If this is an intentional upstream update, use candidate verification first:

```sh
make repo/verify-submodule-candidate
```

Then run the relevant runtime verification, such as:

```sh
make dist/dmg/dev/verify
```

Only after the candidate is reviewed and runtime smoke passes should the new commit be added to
`config/upstream-vitalserver-contract.json` `approvedCommits`.

## Prevention

Do not rely on compile errors to discover upstream drift. The submodule contract gate is part of the
release review path, so upstream contract drift fails before package or DMG compile. Keep IP correction
in the audit proxy and do not reintroduce proxy-header IP logic into upstream VitalServer.
