#!/usr/bin/env python3
from __future__ import annotations

import socket
import sys


def is_free(host: str, port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        try:
            sock.bind((host, port))
        except OSError:
            return False
        return True


def main() -> int:
    if len(sys.argv) != 4:
        print("usage: find_free_port.py HOST START_PORT END_PORT", file=sys.stderr)
        return 2

    host = sys.argv[1]
    start_port = int(sys.argv[2])
    end_port = int(sys.argv[3])
    if start_port > end_port:
        print("START_PORT must be less than or equal to END_PORT", file=sys.stderr)
        return 2

    for port in range(start_port, end_port + 1):
        if is_free(host, port):
            print(port)
            return 0

    print(f"no available port in {start_port}-{end_port} for {host}", file=sys.stderr)
    return 1


if __name__ == "__main__":
    raise SystemExit(main())
