"""Bed command-line workflows."""

from __future__ import annotations

import argparse

from tirosh_vitalserver.testkit.domain.bed import beds_for_room_names, create_beds


def add_bed_parsers(
    subparsers: argparse._SubParsersAction[argparse.ArgumentParser],
) -> None:
    """Register bed domain commands."""

    parser = subparsers.add_parser(
        "create-beds",
        help="Create explicit test bed identities",
        description=(
            "Create bed room names and derived VitalServer bed ids. Pass the "
            "room names to recorder commands with --bed-room-name."
        ),
    )
    selector = parser.add_mutually_exclusive_group(required=True)
    selector.add_argument(
        "--count",
        type=int,
        help="Number of test beds to create",
    )
    selector.add_argument(
        "--room-name",
        action="append",
        default=[],
        help="Explicit bed room name. Repeat to create multiple named beds",
    )
    parser.add_argument(
        "--prefix",
        default="testkit-bed",
        help="Room name prefix",
    )
    parser.add_argument(
        "--admin-user-id",
        default="admin",
        help="Admin user id used by VitalServer to derive bed ids",
    )
    parser.set_defaults(command=run_create_beds)


def run_create_beds(args: argparse.Namespace) -> int:
    """Print fresh test bed identities."""

    if args.room_name:
        beds = beds_for_room_names(
            tuple(args.room_name),
            admin_user_id=args.admin_user_id,
        )
    else:
        beds = create_beds(
            count=args.count,
            prefix=args.prefix,
            admin_user_id=args.admin_user_id,
        )

    for bed in beds:
        print(f"bed: room={bed.room_name} bed_id={bed.bed_id}")

    return 0
