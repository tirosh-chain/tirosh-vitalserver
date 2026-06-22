from __future__ import annotations

import re
from dataclasses import dataclass
from enum import StrEnum
from fnmatch import fnmatchcase
from re import Pattern


class RelayScope(StrEnum):
    WAVEFORM_TREND_ONLY = "waveform_trend_only"
    VITAL_RECONSTRUCTION = "vital_reconstruction"


class DecisionReason(StrEnum):
    ALLOWED = "allowed"
    DENIED = "denied"
    NO_ALLOW_MATCH = "no_allow_match"


@dataclass(frozen=True)
class KeyDecision:
    should_copy: bool
    reason: DecisionReason
    matched_rule: str | None = None


@dataclass(frozen=True)
class KeyFilterPolicy:
    allow_regexes: tuple[Pattern[str], ...]
    deny_globs: tuple[str, ...]

    def decide(self, key: str) -> KeyDecision:
        for glob in self.deny_globs:
            if fnmatchcase(key, glob):
                return KeyDecision(
                    should_copy=False,
                    reason=DecisionReason.DENIED,
                    matched_rule=glob,
                )

        for regex in self.allow_regexes:
            if regex.fullmatch(key):
                return KeyDecision(
                    should_copy=True,
                    reason=DecisionReason.ALLOWED,
                    matched_rule=regex.pattern,
                )

        return KeyDecision(should_copy=False, reason=DecisionReason.NO_ALLOW_MATCH)


WAVEFORM_TREND_ALLOW_REGEXES: tuple[str, ...] = (
    r"^[0-9a-f]{40}[0-9]+\.[0-9]+$",
    r"^dts_[0-9a-f]{40}$",
    r"^dts_trend_result_[0-9a-f]{40}$",
    r"^trend_[0-9a-f]{40}_[0-9]+$",
)

VITAL_RECONSTRUCTION_ALLOW_REGEXES: tuple[str, ...] = (
    *WAVEFORM_TREND_ALLOW_REGEXES,
    r"^beds$",
    r"^beds:[0-9a-f]{40}$",
    r"^vrs$",
    r"^vrs:[A-Za-z0-9_.:-]+$",
    r"^utimes$",
    r"^utime_[0-9a-f]{40}$",
    r"^utime_[A-Za-z0-9_.:-]+$",
    r"^vrver_[A-Za-z0-9_.:-]+$",
    r"^devs_[0-9a-f]{40}$",
    r"^dtapp_[0-9a-f]{40}$",
    r"^filts_[0-9a-f]{40}$",
    r"^ptcon_[0-9a-f]{40}$",
)

RECORDER_NETWORK_CONTEXT_ALLOW_REGEXES: tuple[str, ...] = (
    r"^ip_[A-Za-z0-9_.:-]+$",
    r"^info_[A-Za-z0-9_.:-]+$",
    r"^vrconf_[A-Za-z0-9_.:-]+$",
)

DEFAULT_DENY_GLOBS: tuple[str, ...] = (
    "sess:*",
    "users",
    "users:*",
    "ws_ticket:*",
    "auth:*",
    "token:*",
    "credential:*",
    "secret:*",
    "account_lockout:*",
    "login_attempt:*",
    "rate_limit:*",
    "vitalserver:audit_events",
    "websocket:*",
    "session:*:hct",
)


def relay_key_filter_policy(
    *,
    scope: RelayScope,
    include_recorder_network_context: bool,
) -> KeyFilterPolicy:
    allow_regexes = list(_allow_regexes_for_scope(scope))
    if include_recorder_network_context:
        allow_regexes.extend(RECORDER_NETWORK_CONTEXT_ALLOW_REGEXES)
    return KeyFilterPolicy(
        allow_regexes=tuple(re.compile(pattern) for pattern in allow_regexes),
        deny_globs=DEFAULT_DENY_GLOBS,
    )


def _allow_regexes_for_scope(scope: RelayScope) -> tuple[str, ...]:
    if scope == RelayScope.WAVEFORM_TREND_ONLY:
        return WAVEFORM_TREND_ALLOW_REGEXES
    if scope == RelayScope.VITAL_RECONSTRUCTION:
        return VITAL_RECONSTRUCTION_ALLOW_REGEXES
    raise ValueError(f"unsupported relay scope: {scope}")
