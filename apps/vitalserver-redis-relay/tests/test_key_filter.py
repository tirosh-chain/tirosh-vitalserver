from vitalserver_redis_relay.key_filter import (
    DecisionReason,
    RelayScope,
    relay_key_filter_policy,
)


def test_waveform_scope_allows_frame_and_trend_keys_only() -> None:
    policy = relay_key_filter_policy(
        scope=RelayScope.WAVEFORM_TREND_ONLY,
        include_recorder_network_context=False,
    )

    assert policy.decide("a" * 40 + "1778392870.112").should_copy is True
    assert policy.decide("dts_" + "a" * 40).should_copy is True
    assert policy.decide("trend_" + "a" * 40 + "_1778392860").should_copy is True
    assert policy.decide("beds").reason == DecisionReason.NO_ALLOW_MATCH


def test_vital_reconstruction_scope_allows_context_keys() -> None:
    policy = relay_key_filter_policy(
        scope=RelayScope.VITAL_RECONSTRUCTION,
        include_recorder_network_context=False,
    )

    assert policy.decide("beds").should_copy is True
    assert policy.decide("beds:" + "a" * 40).should_copy is True
    assert policy.decide("vrs").should_copy is True
    assert policy.decide("vrs:VR_123").should_copy is True
    assert policy.decide("devs_" + "a" * 40).should_copy is True
    assert policy.decide("ptcon_" + "a" * 40).should_copy is True


def test_recorder_network_context_is_explicit() -> None:
    base = relay_key_filter_policy(
        scope=RelayScope.VITAL_RECONSTRUCTION,
        include_recorder_network_context=False,
    )
    with_network = relay_key_filter_policy(
        scope=RelayScope.VITAL_RECONSTRUCTION,
        include_recorder_network_context=True,
    )

    assert base.decide("ip_VR_123").should_copy is False
    assert with_network.decide("ip_VR_123").should_copy is True
    assert with_network.decide("info_VR_123").should_copy is True
    assert with_network.decide("vrconf_VR_123").should_copy is True


def test_denylist_takes_precedence_over_allowlist() -> None:
    policy = relay_key_filter_policy(
        scope=RelayScope.VITAL_RECONSTRUCTION,
        include_recorder_network_context=True,
    )

    assert policy.decide("users").reason == DecisionReason.DENIED
    assert policy.decide("token:abc").reason == DecisionReason.DENIED
    assert policy.decide("vitalserver:audit_events").reason == DecisionReason.DENIED
