from __future__ import annotations

import argparse


def run_render_template(args: argparse.Namespace) -> int:
    content = args.template.read_text(encoding="utf-8")
    for raw_value in args.var:
        key, separator, value = raw_value.partition("=")
        if not separator or not key:
            raise SystemExit(f"error: invalid --var value: {raw_value}")
        content = content.replace("${" + key + "}", value)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(content, encoding="utf-8")
    return 0
