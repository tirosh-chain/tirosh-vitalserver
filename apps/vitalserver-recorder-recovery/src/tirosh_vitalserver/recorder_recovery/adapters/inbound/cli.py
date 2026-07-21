"""Command line interface for recorder raw archive recovery."""

from __future__ import annotations

import argparse
from pathlib import Path

from tirosh_vitalserver.core.domain.vital_file import (
    assert_vital_filenames,
    iter_vital_files,
)
from tirosh_vitalserver.recorder_recovery.adapters.outbound import (
    SqliteRecoveryArtifactRegistry,
    VitalServerClient,
)
from tirosh_vitalserver.recorder_recovery.application.assertions import (
    assert_transfer_success,
)
from tirosh_vitalserver.recorder_recovery.application.usecases.recover import (
    RawArchiveVitalExportRequest,
    RawArchiveVitalRecoveryRequest,
    export_raw_archive_vital,
    export_result_to_document,
    recover_raw_archive_vital,
    recovery_result_to_document,
    transfer_summary_to_document,
)
from tirosh_vitalserver.recorder_recovery.application.usecases.upload import (
    upload_vital_files,
)


def build_parser() -> argparse.ArgumentParser:
    """Return the recorder recovery CLI argument parser."""

    parser = argparse.ArgumentParser(prog="vitalserver-recorder-recovery")
    subparsers = parser.add_subparsers(dest="command_name", required=True)

    upload_parser = subparsers.add_parser(
        "upload-vital",
        help="Upload .vital files with multipart/form-data",
    )
    add_upload_args(upload_parser)
    upload_parser.add_argument("path", type=Path, help=".vital file or directory path")
    upload_parser.set_defaults(command=run_upload_vital)

    export_parser = subparsers.add_parser(
        "export-raw-archive-vital",
        help="Export recorder-ingress raw archive JSONL into .vital files",
    )
    export_parser.add_argument(
        "raw_archive_path",
        type=Path,
        help="recorder-ingress send-data raw archive JSONL path",
    )
    add_registry_path_arg(export_parser)
    export_parser.add_argument(
        "--output-dir",
        type=Path,
        required=True,
        help="Directory where generated .vital files will be written",
    )
    export_parser.set_defaults(command=run_export_raw_archive_vital)

    recover_parser = subparsers.add_parser(
        "recover-raw-archive-vital",
        help="Export recorder-ingress raw archive JSONL and upload generated files",
    )
    add_upload_args(recover_parser)
    recover_parser.add_argument(
        "raw_archive_path",
        type=Path,
        help="recorder-ingress send-data raw archive JSONL path",
    )
    add_registry_path_arg(recover_parser)
    recover_parser.add_argument(
        "--output-dir",
        type=Path,
        required=True,
        help="Directory where generated .vital files will be written before upload",
    )
    recover_parser.set_defaults(command=run_recover_raw_archive_vital)

    serve_parser = subparsers.add_parser(
        "serve",
        help="Serve the recorder recovery HTTP API",
    )
    serve_parser.add_argument("--host", default="0.0.0.0")
    serve_parser.add_argument("--port", type=int, default=18082)
    serve_parser.set_defaults(command=run_serve)

    return parser


def add_upload_args(parser: argparse.ArgumentParser) -> None:
    """Add shared VitalServer upload arguments."""

    parser.add_argument(
        "--vitalserver-url",
        default="http://localhost",
        help="VitalServer base URL",
    )
    parser.add_argument("--timeout", type=float, default=30.0)
    parser.add_argument("--concurrency", type=int, default=1)
    parser.add_argument("--repeat", type=int, default=1)
    parser.add_argument("--max-failure-rate", type=float, default=0.0)
    parser.add_argument(
        "--vrcode",
        default=None,
        help="Optional recorder code form field. Upstream /upload does not require it.",
    )
    parser.add_argument("--endpoint", default="/upload")
    parser.add_argument(
        "--skip-filename-check",
        action="store_true",
        help="Skip bedname_yymmdd_hhmmss.vital filename validation",
    )


def add_registry_path_arg(parser: argparse.ArgumentParser) -> None:
    """Add the durable recovery artifact registry location."""

    parser.add_argument(
        "--registry-path",
        type=Path,
        default=None,
        help=(
            "SQLite artifact registry path; default is "
            "<output-dir-parent>/recovery-artifacts.sqlite3"
        ),
    )


def run_upload_vital(args: argparse.Namespace) -> int:
    """Upload one file or a directory of `.vital` files to VitalServer."""

    payloads = iter_vital_files(args.path)
    if not args.skip_filename_check:
        assert_vital_filenames(payloads)

    client = VitalServerClient(args.vitalserver_url, timeout=args.timeout)
    summary = upload_vital_files(
        client,
        payloads,
        vrcode=args.vrcode,
        concurrency=args.concurrency,
        repeat=args.repeat,
        endpoint=args.endpoint,
    )
    print(transfer_summary_to_document(summary))
    assert_transfer_success(summary, max_failure_rate=args.max_failure_rate)
    return 0


def run_export_raw_archive_vital(args: argparse.Namespace) -> int:
    """Export recorder-ingress raw archive JSONL to `.vital` artifacts."""

    result = export_raw_archive_vital(
        RawArchiveVitalExportRequest(
            raw_archive_path=args.raw_archive_path,
            output_dir=args.output_dir,
        ),
        registry=SqliteRecoveryArtifactRegistry(registry_path(args)),
    )
    print(export_result_to_document(result))
    return 0


def run_recover_raw_archive_vital(args: argparse.Namespace) -> int:
    """Export recorder-ingress raw archive JSONL and upload generated files."""

    result = recover_raw_archive_vital(
        RawArchiveVitalRecoveryRequest(
            raw_archive_path=args.raw_archive_path,
            output_dir=args.output_dir,
            vitalserver_url=args.vitalserver_url,
            endpoint=args.endpoint,
            vrcode=args.vrcode,
            timeout=args.timeout,
            concurrency=args.concurrency,
            repeat=args.repeat,
            max_failure_rate=args.max_failure_rate,
            skip_filename_check=args.skip_filename_check,
        ),
        registry=SqliteRecoveryArtifactRegistry(registry_path(args)),
    )
    print(recovery_result_to_document(result))
    return 0


def registry_path(args: argparse.Namespace) -> Path:
    """Resolve the documented CLI registry path preset."""

    if args.registry_path is not None:
        return args.registry_path
    return args.output_dir.parent / "recovery-artifacts.sqlite3"


def run_serve(args: argparse.Namespace) -> int:
    """Run the HTTP API server."""

    import uvicorn

    uvicorn.run(
        "tirosh_vitalserver.recorder_recovery.adapters.inbound.api.app:app",
        host=args.host,
        port=args.port,
    )
    return 0


def main(argv: list[str] | None = None) -> int:
    """CLI entry point."""

    parser = build_parser()
    args = parser.parse_args(argv)
    return int(args.command(args))


if __name__ == "__main__":
    raise SystemExit(main())
