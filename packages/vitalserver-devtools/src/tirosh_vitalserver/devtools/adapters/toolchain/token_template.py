from __future__ import annotations

from pathlib import Path

from tirosh_vitalserver.devtools.core.toolchain import (
    parse_template_variables,
    render_token_template,
)


def run_render_template(template: Path, output: Path, variables: list[str]) -> int:
    content = template.read_text(encoding="utf-8")
    rendered = render_token_template(content, parse_template_variables(variables))
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(rendered, encoding="utf-8")
    return 0
