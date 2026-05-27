from __future__ import annotations

from tirosh_vitalserver.devtools.adapters.toolchain.git_checks import (
    run_require_branch,
)
from tirosh_vitalserver.devtools.adapters.toolchain.token_template import (
    run_render_template,
)
from tirosh_vitalserver.devtools.application.inputs import (
    RenderTemplateInput,
    RequireGitBranchInput,
)


def require_git_branch(input: RequireGitBranchInput) -> int:
    return run_require_branch(input.branch)


def render_template(input: RenderTemplateInput) -> int:
    return run_render_template(input.template, input.output, input.var)
