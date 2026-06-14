from __future__ import annotations

import configparser
import subprocess
from pathlib import Path

from tirosh_vitalserver.devtools.core.upstream_vitalserver_contract import (
    UpstreamVitalServerContractManifest,
    UpstreamVitalServerState,
    manifest_files,
)


def read_upstream_vitalserver_state(
    repo_root: Path,
    manifest: UpstreamVitalServerContractManifest,
) -> UpstreamVitalServerState:
    submodule_dir = repo_root / manifest.submodule_path
    submodule_url, submodule_url_error = _read_submodule_url(
        repo_root / ".gitmodules",
        manifest.submodule_path,
    )
    commit, commit_error = _git_output(submodule_dir, ["rev-parse", "HEAD"])
    dirty_status, dirty_status_error = _git_output(
        submodule_dir,
        ["status", "--porcelain"],
    )
    files: dict[str, str] = {}
    file_errors: dict[str, str] = {}

    for relative_path in manifest_files(manifest):
        path = submodule_dir / relative_path
        try:
            files[relative_path] = path.read_text(encoding="utf-8")
        except FileNotFoundError:
            file_errors[relative_path] = f"missing: {path}"
        except OSError as error:
            file_errors[relative_path] = f"{type(error).__name__}: {error}"
        except UnicodeDecodeError as error:
            file_errors[relative_path] = f"UnicodeDecodeError: {error}"

    return UpstreamVitalServerState(
        submodule_url=submodule_url,
        submodule_url_error=submodule_url_error,
        commit=commit,
        commit_error=commit_error,
        dirty_status=dirty_status,
        dirty_status_error=dirty_status_error,
        files=files,
        file_errors=file_errors,
    )


def _read_submodule_url(
    gitmodules: Path,
    submodule_path: str,
) -> tuple[str | None, str | None]:
    parser = configparser.ConfigParser()
    try:
        with gitmodules.open(encoding="utf-8") as file:
            parser.read_file(file)
    except FileNotFoundError:
        return None, f"missing: {gitmodules}"
    except (OSError, configparser.Error) as error:
        return None, f"{type(error).__name__}: {error}"

    for section in parser.sections():
        if parser.get(section, "path", fallback=None) == submodule_path:
            url = parser.get(section, "url", fallback=None)
            if url:
                return url, None
            return None, f"missing url for submodule path {submodule_path}"
    return None, f"missing submodule path {submodule_path}"


def _git_output(cwd: Path, args: list[str]) -> tuple[str | None, str | None]:
    try:
        output = subprocess.check_output(
            ["git", *args],
            cwd=cwd,
            stderr=subprocess.STDOUT,
            text=True,
        )
    except FileNotFoundError:
        return None, "git executable not found"
    except subprocess.CalledProcessError as error:
        return None, (error.output or str(error)).strip()
    except OSError as error:
        return None, f"{type(error).__name__}: {error}"
    return output.strip(), None
