"""External request schemas for the TestKit API."""

from __future__ import annotations

from pathlib import Path
from typing import Self

from pydantic import ConfigDict, Field, model_validator

from tirosh_vitalserver.testkit.application.recorder_session import (
    RecorderCondition,
    RecorderScenarioWindow,
    RecorderSessionOutput,
    RecorderSource,
    RecorderSourceType,
    RecorderTestScenario,
    VirtualRecorderSessionRequest,
)
from tirosh_vitalserver.testkit.application.usecases.recorder.real_vital_sample import (
    RealVitalSampleScenario,
)
from tirosh_vitalserver.testkit.domain.signal import SignalQualityProfile
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


class RecorderScenarioWindowRequest(ExternalSchema):
    """Request body fragment for a scenario source window."""

    model_config = ConfigDict(populate_by_name=True, strict=False)

    start_offset_seconds: float | None = Field(
        default=None,
        alias="startOffsetSeconds",
        ge=0,
    )
    duration_seconds: float | None = Field(
        default=None,
        alias="durationSeconds",
        ge=0,
    )

    def to_domain(self) -> RecorderScenarioWindow:
        """Convert API window input to the application contract."""

        return RecorderScenarioWindow(
            start_offset_seconds=self.start_offset_seconds,
            duration_seconds=self.duration_seconds,
        )


class RecorderSessionOutputRequest(ExternalSchema):
    """Request body fragment for session output policy."""

    model_config = ConfigDict(populate_by_name=True, strict=False)

    export_vital: bool = Field(default=False, alias="exportVital")
    upload_vital: bool = Field(default=False, alias="uploadVital")
    vital_upload_endpoint: str = Field(default="/upload", alias="vitalUploadEndpoint")

    def to_domain(self) -> RecorderSessionOutput:
        """Convert API output input to the application contract."""

        return RecorderSessionOutput(
            export_vital=self.export_vital,
            upload_vital=self.upload_vital,
            vital_upload_endpoint=self.vital_upload_endpoint,
        )


class RecorderSourceRequest(ExternalSchema):
    """Request body fragment for an explicit recorder source."""

    model_config = ConfigDict(populate_by_name=True, strict=False)

    source_type: RecorderSourceType = Field(alias="type")
    path: Path | None = None
    scenario: RealVitalSampleScenario | None = None
    start_offset_seconds: float = Field(default=0.0, alias="startOffsetSeconds")
    duration_seconds: int = Field(default=120, alias="durationSeconds")

    def to_domain(self) -> RecorderSource:
        """Convert external source input into the application contract."""

        return RecorderSource(
            source_type=self.source_type,
            path=self.path,
            scenario=self.scenario,
            start_offset_seconds=self.start_offset_seconds,
            duration_seconds=self.duration_seconds,
        )


class StartVirtualRecordersRequest(ExternalSchema):
    """Request body for starting a virtual VRecorder session."""

    model_config = ConfigDict(populate_by_name=True, strict=False)

    target_url: str = Field(alias="targetUrl")
    recorders: int = Field(default=1, alias="recorderCount", ge=1)
    bedroom_name: str = Field(default="TestBedroom", alias="bedroomName")
    bed_room_names: tuple[str, ...] = Field(default=(), alias="bedRoomNames")
    scenario: RecorderTestScenario = RecorderTestScenario.NORMAL_MONITORING
    window: RecorderScenarioWindowRequest | None = None
    output: RecorderSessionOutputRequest = Field(
        default_factory=RecorderSessionOutputRequest
    )
    vrcode: str | None = None
    version: str = "testkit"
    signal_quality: SignalQualityProfile = Field(
        default=SignalQualityProfile.CLEAN,
        alias="signalQuality",
    )
    recorder_condition: RecorderCondition = Field(
        default=RecorderCondition.NORMAL,
        alias="recorderCondition",
    )
    source: RecorderSourceRequest | None = None
    real_sample_key: str | None = Field(default=None, alias="realSampleKey")
    interval_seconds: float = Field(default=1.0, alias="intervalSeconds")
    max_messages: int | None = Field(default=None, alias="maxMessages")
    shift_time: bool = Field(default=True, alias="shiftTime")
    generate_frames: bool = Field(default=True, alias="generateFrames")

    def to_session_request(self) -> VirtualRecorderSessionRequest:
        """Convert API input into the application request contract."""

        return VirtualRecorderSessionRequest(
            target_url=self.target_url,
            recorders=self.recorders,
            bedroom_name=self.bedroom_name,
            bed_room_names=self.bed_room_names,
            scenario=self.scenario,
            window=None if self.window is None else self.window.to_domain(),
            output=self.output.to_domain(),
            vrcode=self.vrcode,
            version=self.version,
            signal_quality=self.signal_quality,
            recorder_condition=self.recorder_condition,
            source=None if self.source is None else self.source.to_domain(),
            real_sample_key=self.real_sample_key,
            interval_seconds=self.interval_seconds,
            max_messages=self.max_messages,
            shift_time=self.shift_time,
            generate_frames=self.generate_frames,
        )


class DeleteVirtualRecorderRequest(ExternalSchema):
    """Request body for deleting one VRecorder from VitalServer."""

    model_config = ConfigDict(populate_by_name=True, strict=False)

    target_url: str = Field(alias="targetUrl")
    vrcode: str


class RestartVirtualRecorderSessionRequest(ExternalSchema):
    """Request body for reconnecting a stopped session to selected beds."""

    model_config = ConfigDict(populate_by_name=True, strict=False)

    bedroom_name: str | None = Field(default=None, alias="bedroomName")
