from __future__ import annotations

from enum import StrEnum


class ComposeAction(StrEnum):
    UP = "up"
    STOP = "stop"


class RuntimeObservationAction(StrEnum):
    WATCH = "watch"
    ONCE = "once"


class ContainerLogAction(StrEnum):
    WATCH = "watch"
    ONCE = "once"


class ObservationPhase(StrEnum):
    ACTIVATION_PRE = "activation-pre"
    ACTIVATION_POST = "activation-post"
    ACTIVATION_FAILURE = "activation-failure"
    SHUTDOWN_PRE_STOP = "shutdown-pre-stop"
    SHUTDOWN_POST_SYNC = "shutdown-post-sync"
    SHUTDOWN_POWEROFF_REQUESTED = "shutdown-poweroff-requested"
    SHUTDOWN_FAILURE = "shutdown-failure"
    REPAIR_PRE = "repair-pre"
    REPAIR_FAILURE = "repair-failure"
    MANUAL = "manual"
