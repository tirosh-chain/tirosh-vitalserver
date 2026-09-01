from importlib import import_module


def test_testkit_package_is_importable() -> None:
    testkit = import_module("tirosh_vitalserver.testkit")

    assert testkit.__version__ == "0.1.1"


def test_hl7_polling_module_is_importable() -> None:
    hl7 = import_module("tirosh_vitalserver.testkit.hl7")

    assert callable(hl7.create_hl7_poller)
    assert callable(hl7.create_hl7_decoder)
