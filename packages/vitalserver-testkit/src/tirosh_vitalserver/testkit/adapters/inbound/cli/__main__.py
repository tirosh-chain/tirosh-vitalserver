"""Compatibility wrapper for `python -m` CLI execution."""

from __future__ import annotations

from tirosh_vitalserver.testkit.cli import main

if __name__ == "__main__":
    raise SystemExit(main())
