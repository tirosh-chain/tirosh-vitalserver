"""External request schemas for the TestKit API."""

from __future__ import annotations

from pydantic import ConfigDict, Field

from tirosh_vitalserver.testkit.application.recorder_session import (
    VirtualRecorderSessionRequest,
)
from tirosh_vitalserver.testkit.domain.signal import RecorderSignalScenario
from tirosh_vitalserver.testkit.schemas.base import ExternalSchema


class StartVirtualRecordersRequest(ExternalSchema):
    """Request body for starting a virtual VRecorder session."""

    model_config = ConfigDict(populate_by_name=True, strict=False)

    target_url: str = Field(alias="targetUrl")
    recorders: int = 1
    vrcode: str | None = None
    version: str = "testkit"
    interval_seconds: float = Field(default=1.0, alias="intervalSeconds")
    duration_seconds: float | None = Field(default=None, alias="durationSeconds")
    max_messages: int | None = Field(default=None, alias="maxMessages")
    shift_time: bool = Field(default=True, alias="shiftTime")
    generate_frames: bool = Field(default=True, alias="generateFrames")
    default_scenario: RecorderSignalScenario = Field(
        default=RecorderSignalScenario.NORMAL,
        alias="defaultScenario",
    )

    def to_session_request(self) -> VirtualRecorderSessionRequest:
        """Convert API input into the application request contract."""

        return VirtualRecorderSessionRequest(
            target_url=self.target_url,
            recorders=self.recorders,
            vrcode=self.vrcode,
            version=self.version,
            interval_seconds=self.interval_seconds,
            duration_seconds=self.duration_seconds,
            max_messages=self.max_messages,
            shift_time=self.shift_time,
            generate_frames=self.generate_frames,
            default_scenario=self.default_scenario,
        )
