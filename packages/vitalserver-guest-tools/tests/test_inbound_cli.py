from __future__ import annotations

import tomllib
from pathlib import Path


def test_guest_tools_console_scripts_are_owned_by_inbound_cli() -> None:
    pyproject = Path(__file__).parents[1] / "pyproject.toml"
    with pyproject.open("rb") as handle:
        document = tomllib.load(handle)

    scripts = document["project"]["scripts"]

    assert scripts
    for target in scripts.values():
        assert target.startswith("tirosh_guest_tools.inbound.cli:")
