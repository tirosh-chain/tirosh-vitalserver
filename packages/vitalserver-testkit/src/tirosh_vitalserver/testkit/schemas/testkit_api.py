"""External request schemas for the TestKit API."""

from __future__ import annotations

from typing import Self

from pydantic import ConfigDict, Field, model_validator

from tirosh_vitalserver.testkit.application.recorder_session import (
    VirtualRecorderSessionRequest,
    VirtualRecorderSessionScenario,
)
from tirosh_vitalserver.testkit.domain.signal import RecorderSignalScenario
from tirosh_vitalserver.testkit.schemas.base import ExternalSchema


class CreateBedsRequest(ExternalSchema):
    """Request body for creating explicit test bed identities."""

    model_config = ConfigDict(populate_by_name=True, strict=False)

    count: int | None = Field(default=None, ge=1)
    room_names: tuple[str, ...] = Field(default=(), alias="roomNames")
    prefix: str = "testbed"
    append_random_suffix: bool = Field(default=True, alias="appendRandomSuffix")
    admin_user_id: str = Field(default="admin", alias="adminUserId")

    @model_validator(mode="after")
    def require_one_bed_selector(self) -> Self:
        """Require either generated or named test beds."""

        if self.count is None and not self.room_names:
            raise ValueError("count or roomNames is required")
        if self.count is not None and self.room_names:
            raise ValueError("count and roomNames cannot be used together")
        if (
            self.count is not None
            and not self.append_random_suffix
            and self.count != 1
        ):
            raise ValueError("appendRandomSuffix=false requires count to be 1")

        return self


class DeleteBedsRequest(ExternalSchema):
    """Request body for deleting selected test bed identities."""

    model_config = ConfigDict(populate_by_name=True, strict=False)

    room_names: tuple[str, ...] = Field(alias="roomNames", min_length=1)
    target_url: str | None = Field(default=None, alias="targetUrl")


class StartVirtualRecordersRequest(ExternalSchema):
    """Request body for starting a virtual VRecorder session."""

    model_config = ConfigDict(populate_by_name=True, strict=False)

    target_url: str = Field(alias="targetUrl")
    recorders: int = 1
    bed_room_names: tuple[str, ...] = Field(alias="bedRoomNames")
    vrcode: str | None = None
    version: str = "testkit"
    interval_seconds: float = Field(default=1.0, alias="intervalSeconds")
    duration_seconds: float | None = Field(default=None, alias="durationSeconds")
    max_messages: int | None = Field(default=None, alias="maxMessages")
    shift_time: bool = Field(default=True, alias="shiftTime")
    generate_frames: bool = Field(default=True, alias="generateFrames")
    scenario: VirtualRecorderSessionScenario = VirtualRecorderSessionScenario.NORMAL
    default_scenario: RecorderSignalScenario = Field(
        default=RecorderSignalScenario.NORMAL,
        alias="defaultScenario",
    )
    export_vital: bool = Field(default=False, alias="exportVital")
    upload_vital: bool = Field(default=False, alias="uploadVital")
    vital_upload_endpoint: str = Field(default="/upload", alias="vitalUploadEndpoint")

    def to_session_request(self) -> VirtualRecorderSessionRequest:
        """Convert API input into the application request contract."""

        return VirtualRecorderSessionRequest(
            target_url=self.target_url,
            recorders=self.recorders,
            bed_room_names=self.bed_room_names,
            vrcode=self.vrcode,
            version=self.version,
            interval_seconds=self.interval_seconds,
            duration_seconds=self.duration_seconds,
            max_messages=self.max_messages,
            shift_time=self.shift_time,
            generate_frames=self.generate_frames,
            scenario=self.scenario,
            default_scenario=self.default_scenario,
            export_vital=self.export_vital,
            upload_vital=self.upload_vital,
            vital_upload_endpoint=self.vital_upload_endpoint,
        )


class DeleteVirtualRecorderRequest(ExternalSchema):
    """Request body for deleting one VRecorder from VitalServer."""

    model_config = ConfigDict(populate_by_name=True, strict=False)

    target_url: str = Field(alias="targetUrl")
    vrcode: str


class RestartVirtualRecorderSessionRequest(ExternalSchema):
    """Request body for reconnecting a stopped session to selected beds."""

    model_config = ConfigDict(populate_by_name=True, strict=False)

    bed_room_names: tuple[str, ...] = Field(default=(), alias="bedRoomNames")
