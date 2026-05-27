from __future__ import annotations

from tirosh_vitalserver.devtools.adapters.build_config import load_config
from tirosh_vitalserver.devtools.application.inputs import ConfigValueInput


def print_config_value(input: ConfigValueInput) -> int:
    value: object = load_config(input.config)
    for key in input.key.split("."):
        if not isinstance(value, dict) or key not in value:
            raise SystemExit(f"error: missing config value: {input.key}")
        value = value[key]
    if isinstance(value, bool):
        print("true" if value else "false")
    elif isinstance(value, int | float | str):
        print(value)
    else:
        raise SystemExit(f"error: config value is not scalar: {input.key}")
    return 0
