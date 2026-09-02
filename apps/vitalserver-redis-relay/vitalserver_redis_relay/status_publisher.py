from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol


class StatusPublishContractError(ValueError):
    pass


@dataclass(frozen=True)
class StatusPublishOutcome:
    publisher: str
    published: bool
    error: str | None = None

    def __post_init__(self) -> None:
        if self.published:
            if self.error is not None:
                raise StatusPublishContractError(
                    "successful status publish outcome must not include an error"
                )
            return
        if self.error is None or not self.error.strip():
            raise StatusPublishContractError(
                "failed status publish outcome requires a non-empty error"
            )


@dataclass(frozen=True)
class StatusPublishResult:
    outcomes: tuple[StatusPublishOutcome, ...]

    def __post_init__(self) -> None:
        if not self.outcomes:
            raise StatusPublishContractError(
                "status publish result requires at least one outcome"
            )

    @property
    def any_published(self) -> bool:
        return any(outcome.published for outcome in self.outcomes)

    def failed_outcomes(self) -> tuple[StatusPublishOutcome, ...]:
        return tuple(outcome for outcome in self.outcomes if not outcome.published)


class StatusPublishError(RuntimeError):
    def __init__(self, result: StatusPublishResult) -> None:
        failures = "; ".join(
            f"{outcome.publisher}: {outcome.error}"
            for outcome in result.failed_outcomes()
        )
        super().__init__(f"redis relay status publish failed: {failures}")
        self.result = result


class StatusPublisherConfigurationError(RuntimeError):
    pass


class StatusPublisher(Protocol):
    def publish(self, document: dict[str, object]) -> StatusPublishResult: ...


class CompositeStatusPublisher:
    def __init__(self, publishers: tuple[StatusPublisher, ...]) -> None:
        if not publishers:
            raise StatusPublisherConfigurationError(
                "at least one status publisher is required"
            )
        self.publishers = publishers

    def publish(self, document: dict[str, object]) -> StatusPublishResult:
        outcomes: list[StatusPublishOutcome] = []
        for publisher in self.publishers:
            result = publisher.publish(document)
            outcomes.extend(result.outcomes)
        return StatusPublishResult(outcomes=tuple(outcomes))
