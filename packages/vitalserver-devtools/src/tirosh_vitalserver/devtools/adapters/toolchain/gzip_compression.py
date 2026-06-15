from __future__ import annotations

import gzip
import os
import shutil
import subprocess
from collections.abc import Sequence
from pathlib import Path

from tirosh_vitalserver.devtools.core.toolchain import (
    normalize_compression_threads,
    parse_compression_threads,
)


def compression_threads(value: int | None) -> int:
    env_value = os.environ.get("VITALSERVER_VM_COMPRESSION_THREADS")
    if env_value:
        return parse_compression_threads(env_value)
    return normalize_compression_threads(value, os.cpu_count() or 1)


def gzip_file(source: Path, output: Path, *, threads: int) -> None:
    temporary = output.with_name(output.name + ".tmp")
    temporary.unlink(missing_ok=True)

    pigz = shutil.which("pigz")
    if pigz:
        print(f"using pigz compression threads={threads}")
        with temporary.open("wb") as output_file:
            subprocess.run(
                [pigz, "-c", "-p", str(threads), str(source)],
                stdout=output_file,
                check=True,
            )
    else:
        print("using Python gzip compression")
        with (
            source.open("rb") as source_file,
            gzip.open(
                temporary,
                "wb",
            ) as output_file,
        ):
            shutil.copyfileobj(source_file, output_file)
    temporary.replace(output)


def validate_gzip_file(output: Path, *, expected_uncompressed_size: int) -> None:
    if not output.is_file() or output.stat().st_size == 0:
        raise SystemExit(
            f"rootfs base gzip validation failed: missing output: {output}"
        )

    actual_uncompressed_size = 0
    try:
        with gzip.open(output, "rb") as input_file:
            for chunk in iter(lambda: input_file.read(1024 * 1024), b""):
                actual_uncompressed_size += len(chunk)
    except (OSError, EOFError, gzip.BadGzipFile) as error:
        raise SystemExit(
            f"rootfs base gzip validation failed: unreadable gzip: {output}: {error}"
        ) from error

    if actual_uncompressed_size != expected_uncompressed_size:
        raise SystemExit(
            "rootfs base gzip validation failed: uncompressed size mismatch: "
            f"{output}: expected={expected_uncompressed_size} "
            f"actual={actual_uncompressed_size}"
        )


def gzip_command(command: Sequence[str], output: Path, *, threads: int) -> None:
    temporary = output.with_name(output.name + ".tmp")
    temporary.unlink(missing_ok=True)

    pigz = shutil.which("pigz")
    if pigz:
        print(f"using pigz compression threads={threads}")
        with temporary.open("wb") as output_file:
            producer = subprocess.Popen(command, stdout=subprocess.PIPE)
            assert producer.stdout is not None
            compressor = subprocess.Popen(
                [pigz, "-c", "-p", str(threads)],
                stdin=producer.stdout,
                stdout=output_file,
            )
            producer.stdout.close()
            producer_status = producer.wait()
            compressor_status = compressor.wait()
        if producer_status != 0 or compressor_status != 0:
            temporary.unlink(missing_ok=True)
            raise SystemExit(producer_status or compressor_status)
    else:
        print("using Python gzip compression")
        with (
            temporary.open("wb") as raw_output,
            gzip.GzipFile(
                fileobj=raw_output,
                mode="wb",
            ) as gzip_output,
        ):
            process = subprocess.Popen(command, stdout=subprocess.PIPE)
            stdout = process.stdout
            assert stdout is not None
            try:
                for chunk in iter(lambda: stdout.read(1024 * 1024), b""):
                    gzip_output.write(chunk)
            finally:
                stdout.close()
            status = process.wait()
            if status != 0:
                temporary.unlink(missing_ok=True)
                raise SystemExit(status)
    temporary.replace(output)
