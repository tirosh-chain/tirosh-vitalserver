from vitaldb_observer.config import load_settings


def test_default_audit_event_limit_matches_recorder_ingress_retention() -> None:
    settings = load_settings({})

    assert settings.audit_event_limit == 10_000


def test_explicit_audit_event_limit_is_preserved() -> None:
    settings = load_settings({"VITALDB_OBSERVER_AUDIT_EVENT_LIMIT": "12000"})

    assert settings.audit_event_limit == 12_000
