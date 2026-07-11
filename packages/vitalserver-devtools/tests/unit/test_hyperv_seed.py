from pathlib import Path
import subprocess
import sys


ROOT = Path(__file__).resolve().parents[4]
BUILDER = ROOT / "scripts/build_hyperv_seed.py"


def test_hyperv_seed_has_static_network_and_persistent_native_mounts(
    tmp_path: Path,
) -> None:
    hdiutil = tmp_path / "hdiutil"
    hdiutil.write_text(
        "#!/bin/sh\n"
        "output=\n"
        "previous=\n"
        "for argument do\n"
        "  if [ \"$previous\" = -o ]; then output=$argument; fi\n"
        "  previous=$argument\n"
        "  source=$argument\n"
        "done\n"
        "cat \"$source\"/* > \"$output\"\n",
        encoding="utf-8",
    )
    hdiutil.chmod(0o755)
    output = tmp_path / "seed.iso"

    subprocess.run(
        [
            sys.executable,
            str(BUILDER),
            "--run-id",
            "run-1",
            "--hdiutil",
            str(hdiutil),
            "--output",
            str(output),
        ],
        check=True,
    )

    content = output.read_text(encoding="utf-8")
    assert "instance-id: vitalserver-hyperv-run-1" in content
    assert "driver: hv_netvsc" in content
    assert "addresses: [172.24.0.2/24]" in content
    assert "via: 172.24.0.1" in content
    assert "LABEL=vital-runtime /mnt/runtime" in content
    assert "/opt/vitalserver /mnt/tirosh none bind" in content
    assert "/opt/vitalserver/hyperv-guest/bootstrap.sh" in content


def test_hyperv_seed_rejects_host_outside_guest_network(tmp_path: Path) -> None:
    fake = tmp_path / "hdiutil"
    fake.write_text("#!/bin/sh\nexit 0\n", encoding="utf-8")
    fake.chmod(0o755)
    result = subprocess.run(
        [
            sys.executable,
            str(BUILDER),
            "--run-id",
            "run-1",
            "--host-address",
            "10.0.0.1",
            "--hdiutil",
            str(fake),
            "--output",
            str(tmp_path / "seed.iso"),
        ],
        text=True,
        capture_output=True,
    )

    assert result.returncode != 0
    assert "addresses are incompatible" in result.stderr
