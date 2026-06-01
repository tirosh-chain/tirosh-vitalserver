from __future__ import annotations

from enum import StrEnum


class ComposeAction(StrEnum):
    UP = "up"
    TESTKIT_UP = "testkit-up"
    TESTKIT_UP_LOGGED = "testkit-up-logged"
    STOP = "stop"


class RuntimeStateAction(StrEnum):
    WATCH = "watch"
    ONCE = "once"


class ContainerLogAction(StrEnum):
    WATCH = "watch"
    ONCE = "once"
