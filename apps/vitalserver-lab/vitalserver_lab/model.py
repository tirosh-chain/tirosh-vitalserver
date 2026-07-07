from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass, field, replace
from datetime import UTC, datetime
from typing import Protocol
from uuid import uuid4


def utc_now_iso() -> str:
    return datetime.now(UTC).replace(microsecond=0).isoformat().replace("+00:00", "Z")


@dataclass(frozen=True)
class LabScenario:
    scenario_id: str
    name: str
    category: str
    description: str

    def as_json(self) -> dict[str, str]:
        return {
            "scenarioId": self.scenario_id,
            "name": self.name,
            "category": self.category,
            "description": self.description,
        }


@dataclass(frozen=True)
class LabVitalFile:
    display_name: str
    relative_path: str
    guest_path: str
    size_bytes: int
    modified_at: str

    def as_json(self) -> dict[str, object]:
        return {
            "displayName": self.display_name,
            "relativePath": self.relative_path,
            "guestPath": self.guest_path,
            "sizeBytes": self.size_bytes,
            "modifiedAt": self.modified_at,
        }


@dataclass(frozen=True)
class LabSessionCreateInput:
    scenario_id: str
    name: str
    recorder_count: int
    target_url: str | None
    bed_room_names: tuple[str, ...] = ()
    vital_file_path: str | None = None


@dataclass(frozen=True)
class LabBedCreateInput:
    count: int
    room_names: tuple[str, ...]
    prefix: str
    target_url: str | None = None


@dataclass(frozen=True)
class LabBedDeleteInput:
    bed_ids: tuple[str, ...] = ()
    room_names: tuple[str, ...] = ()
    session_id: str | None = None


@dataclass(frozen=True)
class LabRecorderCreateInput:
    bed_ids: tuple[str, ...] = ()
    session_id: str | None = None


@dataclass(frozen=True)
class LabRecorderDeleteInput:
    recorder_ids: tuple[str, ...] = ()
    vrcodes: tuple[str, ...] = ()
    session_id: str | None = None


@dataclass
class LabSession:
    session_id: str
    scenario_id: str
    name: str
    recorder_count: int
    target_url: str | None
    bed_room_names: tuple[str, ...]
    vital_file_path: str | None
    state: str
    created_at: str
    updated_at: str

    def as_json(self) -> dict[str, object]:
        return {
            "sessionId": self.session_id,
            "scenarioId": self.scenario_id,
            "name": self.name,
            "recorderCount": self.recorder_count,
            "targetURL": self.target_url,
            "bedRoomNames": list(self.bed_room_names),
            "state": self.state,
            "createdAt": self.created_at,
            "updatedAt": self.updated_at,
        }

    def as_private_json(self) -> dict[str, object]:
        document = self.as_json()
        if self.vital_file_path is not None:
            document["vitalFilePath"] = self.vital_file_path
        return document


@dataclass(frozen=True)
class LabBed:
    bed_id: str
    session_id: str
    name: str
    state: str
    created_at: str
    updated_at: str

    def as_json(self) -> dict[str, object]:
        return {
            "bedId": self.bed_id,
            "sessionId": self.session_id,
            "name": self.name,
            "state": self.state,
            "createdAt": self.created_at,
            "updatedAt": self.updated_at,
        }


@dataclass(frozen=True)
class LabRecorder:
    recorder_id: str
    session_id: str
    bed_id: str
    vrcode: str
    state: str
    created_at: str
    updated_at: str
    messages_sent: int = 0
    last_send_state: str = "notAttempted"
    last_send_at: str | None = None
    last_send_error: str | None = None

    def as_json(self) -> dict[str, object]:
        return {
            "recorderId": self.recorder_id,
            "sessionId": self.session_id,
            "bedId": self.bed_id,
            "vrcode": self.vrcode,
            "state": self.state,
            "createdAt": self.created_at,
            "updatedAt": self.updated_at,
            "messagesSent": self.messages_sent,
            "lastSendState": self.last_send_state,
            "lastSendAt": self.last_send_at,
            "lastSendError": self.last_send_error,
        }


@dataclass(frozen=True)
class LabRecorderExecutionResult:
    recorder_id: str
    messages_sent: int
    last_send_state: str
    last_send_at: str | None
    last_send_error: str | None


class LabSessionStore(Protocol):
    def ensure_ready(self) -> None:
        """Verify that the configured session store is available."""

    def create(self, request: LabSessionCreateInput) -> LabSession:
        """Persist and return a new Lab session."""

    def get(self, session_id: str) -> LabSession | None:
        """Return an existing Lab session, or None when it is explicitly absent."""

    def start(self, session_id: str) -> LabSession | None:
        """Transition an existing Lab session to running."""

    def stop(self, session_id: str) -> LabSession | None:
        """Transition an existing Lab session to stopped."""

    def list_beds(self) -> tuple[LabBed, ...]:
        """Return the Lab-owned bed read model."""

    def list_recorders(self) -> tuple[LabRecorder, ...]:
        """Return the Lab-owned recorder read model."""

    def create_beds(self, request: LabBedCreateInput) -> tuple[LabBed, ...]:
        """Create explicit Lab-managed beds without implicit recorder creation."""

    def delete_beds(self, request: LabBedDeleteInput) -> tuple[LabBed, ...]:
        """Delete explicit Lab-managed beds and attached recorders."""

    def reset_beds(self) -> tuple[LabBed, ...]:
        """Remove all Lab-managed beds and attached recorders."""

    def create_recorders(
        self,
        request: LabRecorderCreateInput,
    ) -> tuple[LabRecorder, ...]:
        """Create explicit Lab-managed recorders for existing beds."""

    def delete_recorders(
        self,
        request: LabRecorderDeleteInput,
    ) -> tuple[LabRecorder, ...]:
        """Delete explicit Lab-managed recorders."""

    def reset_recorders(self) -> tuple[LabRecorder, ...]:
        """Remove all Lab-managed recorders while preserving beds."""

    def save_recorder_execution_results(
        self,
        results: tuple[LabRecorderExecutionResult, ...],
    ) -> None:
        """Persist explicit execution results into the recorder read model."""


class LabSessionStoreUnavailable(Exception):
    def __init__(self, message: str, *, kind: str) -> None:
        super().__init__(message)
        self.message = message
        self.kind = kind


@dataclass
class InMemoryLabSessionStore:
    sessions: dict[str, LabSession] = field(default_factory=dict)
    beds: dict[str, LabBed] = field(default_factory=dict)
    recorders: dict[str, LabRecorder] = field(default_factory=dict)
    id_factory: Callable[[], str] = field(default=lambda: f"lab_{uuid4().hex}")

    def ensure_ready(self) -> None:
        return None

    def create(self, request: LabSessionCreateInput) -> LabSession:
        now = utc_now_iso()
        session = LabSession(
            session_id=self.id_factory(),
            scenario_id=request.scenario_id,
            name=request.name,
            recorder_count=request.recorder_count,
            target_url=request.target_url,
            bed_room_names=resolved_bed_room_names(request),
            vital_file_path=request.vital_file_path,
            state="accepted",
            created_at=now,
            updated_at=now,
        )
        self.sessions[session.session_id] = session
        self._save_session_read_model(session, state="accepted", with_recorders=True)
        return session

    def get(self, session_id: str) -> LabSession | None:
        return self.sessions.get(session_id)

    def start(self, session_id: str) -> LabSession | None:
        session = self.sessions.get(session_id)
        if session is None:
            return None
        session.state = "running"
        session.updated_at = utc_now_iso()
        self._save_session_read_model(session, state="running", with_recorders=True)
        return session

    def stop(self, session_id: str) -> LabSession | None:
        session = self.sessions.get(session_id)
        if session is None:
            return None
        session.state = "stopped"
        session.updated_at = utc_now_iso()
        self._save_session_read_model(session, state="stopped", with_recorders=True)
        return session

    def list_beds(self) -> tuple[LabBed, ...]:
        return tuple(sorted(self.beds.values(), key=lambda bed: bed.bed_id))

    def list_recorders(self) -> tuple[LabRecorder, ...]:
        return tuple(
            sorted(
                self.recorders.values(),
                key=lambda recorder: recorder.recorder_id,
            )
        )

    def save_recorder_execution_results(
        self,
        results: tuple[LabRecorderExecutionResult, ...],
    ) -> None:
        for result in results:
            recorder = self.recorders.get(result.recorder_id)
            if recorder is None:
                raise LabSessionStoreUnavailable(
                    f"Lab recorder read model is missing: {result.recorder_id}",
                    kind="labRecorderReadModelMissing",
                )
            self.recorders[result.recorder_id] = recorder_with_execution_result(
                recorder,
                result,
            )

    def create_beds(self, request: LabBedCreateInput) -> tuple[LabBed, ...]:
        session = LabSession(
            session_id=self.id_factory(),
            scenario_id="manual-lab-beds",
            name=request.prefix,
            recorder_count=request.count,
            target_url=request.target_url,
            bed_room_names=request.room_names,
            vital_file_path=None,
            state="accepted",
            created_at=utc_now_iso(),
            updated_at=utc_now_iso(),
        )
        self.sessions[session.session_id] = session
        self._save_session_read_model(session, state="accepted", with_recorders=False)
        return self.list_beds()

    def delete_beds(self, request: LabBedDeleteInput) -> tuple[LabBed, ...]:
        matches = matching_beds(self.list_beds(), request)
        if not matches:
            raise LabSessionStoreUnavailable(
                "No Lab beds matched the delete request.",
                kind="labBedDeleteTargetMissing",
            )
        matched_bed_ids = {bed.bed_id for bed in matches}
        for bed_id in matched_bed_ids:
            self.beds.pop(bed_id, None)
        for recorder_id, recorder in list(self.recorders.items()):
            if recorder.bed_id in matched_bed_ids:
                self.recorders.pop(recorder_id, None)
        return self.list_beds()

    def reset_beds(self) -> tuple[LabBed, ...]:
        self.beds.clear()
        self.recorders.clear()
        return self.list_beds()

    def create_recorders(
        self,
        request: LabRecorderCreateInput,
    ) -> tuple[LabRecorder, ...]:
        beds = matching_beds_for_recorder_create(self.list_beds(), request)
        if not beds:
            raise LabSessionStoreUnavailable(
                "No Lab beds matched the recorder create request.",
                kind="labRecorderCreateTargetMissing",
            )
        now = utc_now_iso()
        for bed in beds:
            recorder = lab_recorder_for_bed(
                session_id=bed.session_id,
                bed_id=bed.bed_id,
                state=bed.state,
                index=next_recorder_index(self.recorders.values(), bed.session_id),
                created_at=now,
                updated_at=now,
            )
            self.recorders[recorder.recorder_id] = recorder
        return self.list_recorders()

    def delete_recorders(
        self,
        request: LabRecorderDeleteInput,
    ) -> tuple[LabRecorder, ...]:
        matches = matching_recorders(self.list_recorders(), request)
        if not matches:
            raise LabSessionStoreUnavailable(
                "No Lab recorders matched the delete request.",
                kind="labRecorderDeleteTargetMissing",
            )
        for recorder in matches:
            self.recorders.pop(recorder.recorder_id, None)
        return self.list_recorders()

    def reset_recorders(self) -> tuple[LabRecorder, ...]:
        self.recorders.clear()
        return self.list_recorders()

    def _save_session_read_model(
        self,
        session: LabSession,
        *,
        state: str,
        with_recorders: bool,
    ) -> None:
        names = bed_room_names_for_session(
            name=session.name,
            recorder_count=session.recorder_count,
            explicit_names=session.bed_room_names,
        )
        for index, name in enumerate(names, start=1):
            bed = lab_bed_for_session(
                session_id=session.session_id,
                name=name,
                state=state,
                index=index,
                created_at=session.created_at,
                updated_at=session.updated_at,
            )
            self.beds[bed.bed_id] = bed
            if with_recorders:
                recorder = lab_recorder_for_bed(
                    session_id=session.session_id,
                    bed_id=bed.bed_id,
                    state=state,
                    index=index,
                    created_at=session.created_at,
                    updated_at=session.updated_at,
                )
                previous_recorder = self.recorders.get(recorder.recorder_id)
                if previous_recorder is not None:
                    recorder = recorder_with_preserved_execution(
                        recorder,
                        previous_recorder,
                    )
                self.recorders[recorder.recorder_id] = recorder


def resolved_bed_room_names(request: LabSessionCreateInput) -> tuple[str, ...]:
    return bed_room_names_for_session(
        name=request.name,
        recorder_count=request.recorder_count,
        explicit_names=request.bed_room_names,
    )


def bed_room_names_for_session(
    *,
    name: str,
    recorder_count: int,
    explicit_names: tuple[str, ...] = (),
) -> tuple[str, ...]:
    if explicit_names:
        return explicit_names
    if recorder_count == 1:
        return (name,)
    return (name, *(f"{name}-{index}" for index in range(2, recorder_count + 1)))


def lab_bed_for_session(
    *,
    session_id: str,
    name: str,
    state: str,
    index: int,
    created_at: str,
    updated_at: str,
) -> LabBed:
    return LabBed(
        bed_id=f"{session_id}-bed-{index}",
        session_id=session_id,
        name=name,
        state=state,
        created_at=created_at,
        updated_at=updated_at,
    )


def lab_recorder_for_bed(
    *,
    session_id: str,
    bed_id: str,
    state: str,
    index: int,
    created_at: str,
    updated_at: str,
) -> LabRecorder:
    return LabRecorder(
        recorder_id=f"{session_id}-recorder-{index}",
        session_id=session_id,
        bed_id=bed_id,
        vrcode=f"LAB-{session_id}-{index}",
        state=state,
        created_at=created_at,
        updated_at=updated_at,
    )


def matching_beds(
    beds: tuple[LabBed, ...],
    request: LabBedDeleteInput,
) -> tuple[LabBed, ...]:
    bed_ids = set(request.bed_ids)
    room_names = set(request.room_names)
    return tuple(
        bed
        for bed in beds
        if (bed_ids and bed.bed_id in bed_ids)
        or (room_names and bed.name in room_names)
        or (request.session_id is not None and bed.session_id == request.session_id)
    )


def matching_beds_for_recorder_create(
    beds: tuple[LabBed, ...],
    request: LabRecorderCreateInput,
) -> tuple[LabBed, ...]:
    bed_ids = set(request.bed_ids)
    return tuple(
        bed
        for bed in beds
        if (bed_ids and bed.bed_id in bed_ids)
        or (request.session_id is not None and bed.session_id == request.session_id)
    )


def matching_recorders(
    recorders: tuple[LabRecorder, ...],
    request: LabRecorderDeleteInput,
) -> tuple[LabRecorder, ...]:
    recorder_ids = set(request.recorder_ids)
    vrcodes = set(request.vrcodes)
    return tuple(
        recorder
        for recorder in recorders
        if (recorder_ids and recorder.recorder_id in recorder_ids)
        or (vrcodes and recorder.vrcode in vrcodes)
        or (
            request.session_id is not None
            and recorder.session_id == request.session_id
        )
    )


def next_recorder_index(recorders: object, session_id: str) -> int:
    session_recorders = [
        recorder
        for recorder in recorders
        if isinstance(recorder, LabRecorder) and recorder.session_id == session_id
    ]
    return len(session_recorders) + 1


def recorder_with_preserved_execution(
    recorder: LabRecorder,
    previous: LabRecorder,
) -> LabRecorder:
    return replace(
        recorder,
        messages_sent=previous.messages_sent,
        last_send_state=previous.last_send_state,
        last_send_at=previous.last_send_at,
        last_send_error=previous.last_send_error,
    )


def recorder_with_execution_result(
    recorder: LabRecorder,
    result: LabRecorderExecutionResult,
) -> LabRecorder:
    return replace(
        recorder,
        messages_sent=recorder.messages_sent + result.messages_sent,
        last_send_state=result.last_send_state,
        last_send_at=result.last_send_at,
        last_send_error=result.last_send_error,
        updated_at=result.last_send_at or recorder.updated_at,
    )


DEFAULT_SCENARIOS = (
    LabScenario(
        scenario_id="baseline-monitoring",
        name="Baseline Monitoring",
        category="generated",
        description="Stable vital signs for product workflow verification.",
    ),
    LabScenario(
        scenario_id="respiratory-variation",
        name="Respiratory Variation",
        category="generated",
        description="Periodic respiration-linked waveform and value changes.",
    ),
    LabScenario(
        scenario_id="vital-file-replay",
        name="Vital File Replay",
        category="replay",
        description=(
            "Replay a selected .vital file from the configured mounted directory."
        ),
    ),
)
