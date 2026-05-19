from importlib import import_module


def test_testkit_package_is_importable() -> None:
    testkit = import_module("tirosh_vitalserver.testkit")

    assert testkit.__version__ == "0.1.1"
