"""Vital file transfer CLI commands."""

from __future__ import annotations

import argparse
from pathlib import Path

from tirosh_vitalserver.testkit.adapters.inbound.cli.common import (
    add_common_server_args,
    add_load_args,
)
from tirosh_vitalserver.testkit.adapters.inbound.cli.output import print_summary
from tirosh_vitalserver.testkit.adapters.outbound.raw_archive_vital_artifact import (
    RawArchiveVitalFileExporter,
)
from tirosh_vitalserver.testkit.adapters.outbound.vitalserver import VitalServerClient
from tirosh_vitalserver.testkit.application.usecases import (
    assert_transfer_success,
    upload_vital_files,
)
from tirosh_vitalserver.testkit.domain.vital_file import (
    assert_vital_filenames,
    iter_vital_files,
)


def add_vital_file_parsers(
    subparsers: argparse._SubParsersAction[argparse.ArgumentParser],
) -> None:
    """Register commands that operate on `.vital` files."""

    parser = subparsers.add_parser(
        "upload-vital",
        help="Upload .vital files with multipart/form-data",
    )

    add_common_server_args(parser)
    add_load_args(parser)

    parser.add_argument("path", type=Path, help=".vital file or directory path")
    parser.add_argument(
        "--vrcode",
        default=None,
        help="Optional recorder code form field. Upstream /upload does not require it.",
    )
    parser.add_argument(
        "--endpoint",
        default="/upload",
        help="Vital file upload endpoint",
    )
    parser.add_argument(
        "--skip-filename-check",
        action="store_true",
        help="Skip bedname_yymmdd_hhmmss.vital filename validation",
    )

    parser.set_defaults(command=run_upload_vital)

    export_parser = subparsers.add_parser(
        "export-raw-archive-vital",
        help="Export recorder-ingress raw archive JSONL into .vital files",
    )
    export_parser.add_argument(
        "raw_archive_path",
        type=Path,
        help="recorder-ingress send-data raw archive JSONL path",
    )
    export_parser.add_argument(
        "--output-dir",
        type=Path,
        required=True,
        help="Directory where generated .vital files will be written",
    )
    export_parser.set_defaults(command=run_export_raw_archive_vital)

    recover_parser = subparsers.add_parser(
        "recover-raw-archive-vital",
        help=(
            "Export recorder-ingress raw archive JSONL and upload generated "
            ".vital files"
        ),
    )
    add_common_server_args(recover_parser)
    add_load_args(recover_parser)
    recover_parser.add_argument(
        "raw_archive_path",
        type=Path,
        help="recorder-ingress send-data raw archive JSONL path",
    )
    recover_parser.add_argument(
        "--output-dir",
        type=Path,
        required=True,
        help="Directory where generated .vital files will be written before upload",
    )
    recover_parser.add_argument(
        "--vrcode",
        default=None,
        help="Optional recorder code form field. Upstream /upload does not require it.",
    )
    recover_parser.add_argument(
        "--endpoint",
        default="/upload",
        help="Vital file upload endpoint",
    )
    recover_parser.add_argument(
        "--skip-filename-check",
        action="store_true",
        help="Skip bedname_yymmdd_hhmmss.vital filename validation before upload",
    )
    recover_parser.set_defaults(command=run_recover_raw_archive_vital)


def run_upload_vital(args: argparse.Namespace) -> int:
    """Upload one file or a directory of `.vital` files to VitalServer."""

    client = VitalServerClient(args.vitalserver_url, timeout=args.timeout)
    payloads = iter_vital_files(args.path)

    if not args.skip_filename_check:
        assert_vital_filenames(payloads)

    summary = upload_vital_files(
        client,
        payloads,
        vrcode=args.vrcode,
        concurrency=args.concurrency,
        repeat=args.repeat,
        endpoint=args.endpoint,
    )

    print_summary(summary)
    assert_transfer_success(summary, max_failure_rate=args.max_failure_rate)

    return 0


def run_export_raw_archive_vital(args: argparse.Namespace) -> int:
    """Export recorder-ingress raw archive JSONL to `.vital` artifacts."""

    exporter = RawArchiveVitalFileExporter()
    artifacts = exporter.export_raw_archive(args.raw_archive_path, args.output_dir)
    for artifact in artifacts:
        print(
            "exported "
            f"vrcode={artifact.vrcode} "
            f"tracks={artifact.track_count} "
            f"bytes={artifact.size_bytes} "
            f"path={artifact.path}"
        )
    return 0


def run_recover_raw_archive_vital(args: argparse.Namespace) -> int:
    """Export recorder-ingress raw archive JSONL and upload the generated files."""

    exporter = RawArchiveVitalFileExporter()
    artifacts = exporter.export_raw_archive(args.raw_archive_path, args.output_dir)
    for artifact in artifacts:
        print(
            "exported "
            f"vrcode={artifact.vrcode} "
            f"tracks={artifact.track_count} "
            f"bytes={artifact.size_bytes} "
            f"path={artifact.path}"
        )

    payloads = iter_vital_files(args.output_dir)
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

    print_summary(summary)
    assert_transfer_success(summary, max_failure_rate=args.max_failure_rate)
    return 0
