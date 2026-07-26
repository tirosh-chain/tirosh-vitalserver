# Guest wheel uses Python syntax newer than the Guest runtime

> ID: TS-126
> Category: Packaging / Guest bootstrap
> Owner: devtools Guest wheelhouse staging
> Status: resolved

## Symptoms

Golden rootfs compile stops with a current-run failure document:

```text
stage=rootfs-smoke exitCode=1 reason=guest-rootfs-prepare-failed
```

The matching `launcher.log` shows that Guest Tools and its dependencies were
installed successfully, but the rootfs smoke entrypoint failed during import:

```text
SyntaxError: multiple exception types must be parenthesized
```

## Cause

The Host development environment ran Python 3.14, which permits an
unparenthesized multiple-exception clause. The packaged Ubuntu 24.04 Guest runs
Python 3.12, where the same source is invalid. Host tests imported the module
successfully and the wheelhouse verified dependency closure, but neither check
validated the generated wheel against the explicit Guest Python version.

## Fix direction

The repository Host development baseline and shared Python packages now target
Python 3.12, matching the Ubuntu Guest interpreter. Use syntax accepted by that
runtime:

```python
except (UnicodeDecodeError, json.JSONDecodeError):
```

Before dependency download or VM startup, parse every Python module in the
generated Guest Tools wheel using the target's explicit CPython 3.12 grammar.
This independent package-boundary proof remains required even when Host and
Guest versions match. An incompatible module is a Host compile failure and must
not enter the rootfs.

## Prevention

Keep `.python-version`, workspace package metadata, Ruff, and mypy on Python
3.12 while Ubuntu 24.04 owns the Guest interpreter contract. Wheelhouse staging
still validates both dependency closure and source syntax using
`GUEST_RUNTIME_TARGETS[*].python_version`; a Host test pass alone is not package
compatibility proof.

Product and testkit container base images are separate, explicit runtime inputs;
their Dockerfile Python tags are not the Host development interpreter contract.
Changing those images requires their own dependency and runtime acceptance proof.

Do not handle this by changing the Guest image opportunistically or by retrying
the smoke. The wheel and target interpreter are explicit release inputs.

## Checks

```sh
rg -n -C 5 'SyntaxError|rootfs-smoke' \
  .tmp/vitalserver-vm-golden/logs/launcher.log
uv run pytest -q \
  packages/vitalserver-devtools/tests/unit/test_guest_deploy_bundle.py
```

## Related Cases

- TS-069: Golden rootfs proof and current-run boundary
- TS-123: Guest Tools air-gap dependency closure

## Follow-up

- 2026-07-13: Added CPython 3.12 grammar validation to Guest wheelhouse staging
  and corrected the Product Lab HTTP error decoder.
- 2026-07-13: Aligned the Host development baseline and shared workspace
  package metadata with Guest Python 3.12.
