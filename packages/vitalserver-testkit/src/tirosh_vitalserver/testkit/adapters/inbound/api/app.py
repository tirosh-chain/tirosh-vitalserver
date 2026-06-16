"""FastAPI app for controlling TestKit virtual VRecorder sessions."""

import logging
import time
from typing import Annotated, Any

from fastapi import Depends, FastAPI, HTTPException, Query, Request

from tirosh_vitalserver.testkit.adapters.outbound.recorder import (
    SocketIoRecorderManagementClient,
    connect_socketio,
)
from tirosh_vitalserver.testkit.application.bed_registry import BedRegistry
from tirosh_vitalserver.testkit.application.bed_registry.store import (
    BedRegistryStorePort,
)
from tirosh_vitalserver.testkit.application.ports import (
    SessionVitalFileExporterPort,
    SessionVitalFileUploaderPort,
)
from tirosh_vitalserver.testkit.application.recorder_session import (
    VirtualRecorderSessionManager,
    deletion_result_to_document,
    session_snapshot_to_document,
)
from tirosh_vitalserver.testkit.application.recorder_session.store import (
    VirtualRecorderSessionStorePort,
)
from tirosh_vitalserver.testkit.domain.bed import Bed
from tirosh_vitalserver.testkit.errors import (
    ActiveBedAssignmentsExistError,
    BedAlreadyAssignedError,
)
from tirosh_vitalserver.testkit.observability import emit_testkit_event
from tirosh_vitalserver.testkit.schemas.testkit_api import (
    CreateBedsRequest,
    DeleteBedsRequest,
    DeleteVirtualRecorderRequest,
    RestartVirtualRecorderSessionRequest,
    StartVirtualRecordersRequest,
)


def create_testkit_app(
    manager: VirtualRecorderSessionManager | None = None,
    session_store: VirtualRecorderSessionStorePort | None = None,
    bed_registry: BedRegistry | None = None,
    bed_registry_store: BedRegistryStorePort | None = None,
    vital_file_exporter: SessionVitalFileExporterPort | None = None,
    vital_file_uploader: SessionVitalFileUploaderPort | None = None,
) -> FastAPI:
    """Build the TestKit FastAPI application."""

    app = FastAPI(
        title="VitalServer TestKit API",
        version="0.1.0",
    )
    session_manager = manager or VirtualRecorderSessionManager(
        connector=connect_socketio,
        recorder_management=SocketIoRecorderManagementClient(),
        session_store=session_store,
        vital_file_exporter=vital_file_exporter,
        vital_file_uploader=vital_file_uploader,
    )
    beds = bed_registry or BedRegistry(store=bed_registry_store)

    def get_manager() -> VirtualRecorderSessionManager:
        return session_manager

    def get_bed_registry() -> BedRegistry:
        return beds

    @app.middleware("http")
    async def log_api_request(request: Request, call_next: Any) -> Any:
        started = time.perf_counter()
        try:
            response = await call_next(request)
        except Exception as exc:
            emit_testkit_event(
                "api.request.failed",
                level=logging.WARNING,
                method=request.method,
                path=request.url.path,
                elapsed_ms=elapsed_ms(started),
                error=str(exc),
            )
            raise

        emit_testkit_event(
            "api.request",
            level=logging.INFO if request.method != "GET" else logging.DEBUG,
            method=request.method,
            path=request.url.path,
            status_code=response.status_code,
            elapsed_ms=elapsed_ms(started),
        )
        return response

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    @app.post("/beds", status_code=201)
    def create_beds(
        request: CreateBedsRequest,
        registry: Annotated[BedRegistry, Depends(get_bed_registry)],
    ) -> dict[str, list[dict[str, str]]]:
        emit_testkit_event(
            "api.beds.create.requested",
            count=request.count,
            room_names=len(request.room_names),
            prefix=request.prefix,
            admin_user_id=request.admin_user_id,
        )
        try:
            registered_beds = registry.create_beds(
                count=request.count,
                room_names=request.room_names,
                prefix=request.prefix,
                admin_user_id=request.admin_user_id,
            )
        except ValueError as exc:
            emit_testkit_event(
                "api.beds.create.rejected",
                level=logging.WARNING,
                count=request.count,
                room_names=len(request.room_names),
                error=str(exc),
            )
            raise HTTPException(status_code=400, detail=str(exc)) from exc

        emit_testkit_event("api.beds.create.accepted", count=len(registered_beds))

        return {"beds": [bed_to_document(bed) for bed in registered_beds]}

    @app.get("/beds")
    def list_beds(
        registry: Annotated[BedRegistry, Depends(get_bed_registry)],
    ) -> dict[str, list[dict[str, str]]]:
        return {"beds": [bed_to_document(bed) for bed in registry.list_beds()]}

    @app.delete("/beds")
    def delete_beds(
        registry: Annotated[BedRegistry, Depends(get_bed_registry)],
        manager: Annotated[VirtualRecorderSessionManager, Depends(get_manager)],
        target_url: Annotated[str | None, Query(alias="targetUrl")] = None,
    ) -> dict[str, Any]:
        emit_testkit_event("api.beds.reset.requested")
        active_bed_room_names = manager.active_bed_room_names()
        if active_bed_room_names:
            error = ActiveBedAssignmentsExistError(active_bed_room_names)
            emit_testkit_event(
                "api.beds.reset.rejected",
                level=logging.WARNING,
                active_beds=len(active_bed_room_names),
                error=str(error),
            )
            raise HTTPException(status_code=409, detail=str(error)) from error

        deleted = registry.reset_beds()
        cleanup_errors: tuple[str, ...] = ()
        if target_url:
            cleanup_errors = manager.delete_vitalserver_beds(target_url, deleted)
        emit_testkit_event(
            "api.beds.reset.accepted",
            count=len(deleted),
            cleanup_errors=len(cleanup_errors),
        )
        return {
            "beds": [bed_to_document(bed) for bed in deleted],
            "cleanupErrors": list(cleanup_errors),
        }

    @app.post("/beds/delete")
    def delete_selected_beds(
        request: DeleteBedsRequest,
        registry: Annotated[BedRegistry, Depends(get_bed_registry)],
        manager: Annotated[VirtualRecorderSessionManager, Depends(get_manager)],
    ) -> dict[str, Any]:
        emit_testkit_event(
            "api.beds.delete.requested",
            room_names=len(request.room_names),
        )
        try:
            resolved_room_names = registry.require_registered_room_names(
                request.room_names
            )
        except ValueError as exc:
            emit_testkit_event(
                "api.beds.delete.rejected",
                level=logging.WARNING,
                room_names=len(request.room_names),
                error=str(exc),
            )
            raise HTTPException(status_code=400, detail=str(exc)) from exc

        active_bed_room_names = set(manager.active_bed_room_names())
        conflicts = tuple(
            room_name
            for room_name in resolved_room_names
            if room_name in active_bed_room_names
        )
        if conflicts:
            error = ActiveBedAssignmentsExistError(conflicts, operation="delete")
            emit_testkit_event(
                "api.beds.delete.rejected",
                level=logging.WARNING,
                active_beds=len(conflicts),
                error=str(error),
            )
            raise HTTPException(status_code=409, detail=str(error)) from error

        try:
            deleted = registry.delete_beds(resolved_room_names)
        except ValueError as exc:
            emit_testkit_event(
                "api.beds.delete.rejected",
                level=logging.WARNING,
                room_names=len(request.room_names),
                error=str(exc),
            )
            raise HTTPException(status_code=400, detail=str(exc)) from exc

        cleanup_errors: tuple[str, ...] = ()
        if request.target_url:
            cleanup_errors = manager.delete_vitalserver_beds(
                request.target_url,
                deleted,
            )
        emit_testkit_event(
            "api.beds.delete.accepted",
            count=len(deleted),
            cleanup_errors=len(cleanup_errors),
        )
        return {
            "beds": [bed_to_document(bed) for bed in deleted],
            "cleanupErrors": list(cleanup_errors),
        }

    @app.get("/sessions")
    def list_sessions(
        manager: Annotated[VirtualRecorderSessionManager, Depends(get_manager)],
    ) -> dict[str, list[dict[str, Any]]]:
        return {
            "sessions": [
                session_snapshot_to_document(session)
                for session in manager.list_sessions()
            ]
        }

    @app.delete("/sessions")
    def delete_sessions(
        manager: Annotated[VirtualRecorderSessionManager, Depends(get_manager)],
    ) -> dict[str, list[dict[str, Any]]]:
        emit_testkit_event("api.sessions.reset.requested")
        snapshots = manager.delete_all_sessions()
        emit_testkit_event(
            "api.sessions.reset.accepted",
            deleted_sessions=len(snapshots),
        )
        return {
            "sessions": [
                session_snapshot_to_document(snapshot)
                for snapshot in snapshots
            ]
        }

    @app.post("/sessions", status_code=201)
    def start_session(
        request: StartVirtualRecordersRequest,
        manager: Annotated[VirtualRecorderSessionManager, Depends(get_manager)],
        registry: Annotated[BedRegistry, Depends(get_bed_registry)],
    ) -> dict[str, Any]:
        emit_testkit_event(
            "api.session.start.requested",
            target_url=request.target_url,
            recorders=request.recorders,
            beds=len(request.bed_room_names),
            vrcode=request.vrcode,
            interval_seconds=request.interval_seconds,
            duration_seconds=request.duration_seconds,
            max_messages=request.max_messages,
            default_scenario=request.default_scenario.value,
        )
        try:
            session_request = request.to_session_request()
            registry.require_registered_room_names(session_request.bed_room_names)
            snapshot = manager.start_session(session_request)
        except BedAlreadyAssignedError as exc:
            emit_testkit_event(
                "api.session.start.conflicted",
                level=logging.WARNING,
                target_url=request.target_url,
                recorders=request.recorders,
                beds=len(request.bed_room_names),
                error=str(exc),
            )
            raise HTTPException(status_code=409, detail=str(exc)) from exc
        except ValueError as exc:
            emit_testkit_event(
                "api.session.start.rejected",
                level=logging.WARNING,
                target_url=request.target_url,
                recorders=request.recorders,
                beds=len(request.bed_room_names),
                error=str(exc),
            )
            raise HTTPException(status_code=400, detail=str(exc)) from exc

        emit_testkit_event(
            "api.session.start.accepted",
            session_id=snapshot.session_id,
            state=snapshot.state.value,
            target_url=snapshot.request.target_url,
            recorders=snapshot.request.recorders,
            beds=len(snapshot.request.bed_room_names),
            vrcode=snapshot.request.vrcode,
        )
        return session_snapshot_to_document(snapshot)

    @app.post("/recorders/delete")
    def delete_vrecorder(
        request: DeleteVirtualRecorderRequest,
        manager: Annotated[VirtualRecorderSessionManager, Depends(get_manager)],
    ) -> dict[str, Any]:
        emit_testkit_event(
            "api.vrecorder.delete.requested",
            target_url=request.target_url,
            vrcode=request.vrcode,
        )
        try:
            result = manager.delete_vrecorder(
                target_url=request.target_url,
                vrcode=request.vrcode,
            )
        except ValueError as exc:
            emit_testkit_event(
                "api.vrecorder.delete.rejected",
                level=logging.WARNING,
                target_url=request.target_url,
                vrcode=request.vrcode,
                error=str(exc),
            )
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        except RuntimeError as exc:
            emit_testkit_event(
                "api.vrecorder.delete.unavailable",
                level=logging.WARNING,
                target_url=request.target_url,
                vrcode=request.vrcode,
                error=str(exc),
            )
            raise HTTPException(status_code=503, detail=str(exc)) from exc

        return deletion_result_to_document(result)

    @app.get("/sessions/{session_id}")
    def get_session(
        session_id: str,
        manager: Annotated[VirtualRecorderSessionManager, Depends(get_manager)],
    ) -> dict[str, Any]:
        snapshot = manager.get_session(session_id)
        if snapshot is None:
            raise HTTPException(status_code=404, detail="session not found")

        return session_snapshot_to_document(snapshot)

    @app.post("/sessions/{session_id}/stop")
    def stop_session(
        session_id: str,
        manager: Annotated[VirtualRecorderSessionManager, Depends(get_manager)],
    ) -> dict[str, Any]:
        emit_testkit_event("api.session.stop.requested", session_id=session_id)
        snapshot = manager.stop_session(session_id)
        if snapshot is None:
            emit_testkit_event(
                "api.session.stop.missing",
                level=logging.WARNING,
                session_id=session_id,
            )
            raise HTTPException(status_code=404, detail="session not found")

        emit_testkit_event(
            "api.session.stop.accepted",
            session_id=snapshot.session_id,
            state=snapshot.state.value,
        )
        return session_snapshot_to_document(snapshot)

    @app.post("/sessions/{session_id}/upload-vital")
    def retry_vital_upload(
        session_id: str,
        manager: Annotated[VirtualRecorderSessionManager, Depends(get_manager)],
    ) -> dict[str, Any]:
        emit_testkit_event(
            "api.session.vital_upload_retry.requested",
            session_id=session_id,
        )
        snapshot = manager.retry_vital_upload(session_id)
        if snapshot is None:
            emit_testkit_event(
                "api.session.vital_upload_retry.missing",
                level=logging.WARNING,
                session_id=session_id,
            )
            raise HTTPException(status_code=404, detail="session not found")

        emit_testkit_event(
            "api.session.vital_upload_retry.accepted",
            session_id=snapshot.session_id,
            state=snapshot.state.value,
        )
        return session_snapshot_to_document(snapshot)

    @app.post("/sessions/{session_id}/pause")
    def pause_session(
        session_id: str,
        manager: Annotated[VirtualRecorderSessionManager, Depends(get_manager)],
    ) -> dict[str, Any]:
        emit_testkit_event("api.session.pause.requested", session_id=session_id)
        snapshot = manager.pause_session(session_id)
        if snapshot is None:
            emit_testkit_event(
                "api.session.pause.missing",
                level=logging.WARNING,
                session_id=session_id,
            )
            raise HTTPException(status_code=404, detail="session not found")

        emit_testkit_event(
            "api.session.pause.accepted",
            session_id=snapshot.session_id,
            state=snapshot.state.value,
        )
        return session_snapshot_to_document(snapshot)

    @app.post("/sessions/{session_id}/resume")
    def resume_session(
        session_id: str,
        manager: Annotated[VirtualRecorderSessionManager, Depends(get_manager)],
    ) -> dict[str, Any]:
        emit_testkit_event("api.session.resume.requested", session_id=session_id)
        snapshot = manager.resume_session(session_id)
        if snapshot is None:
            emit_testkit_event(
                "api.session.resume.missing",
                level=logging.WARNING,
                session_id=session_id,
            )
            raise HTTPException(status_code=404, detail="session not found")

        emit_testkit_event(
            "api.session.resume.accepted",
            session_id=snapshot.session_id,
            state=snapshot.state.value,
        )
        return session_snapshot_to_document(snapshot)

    @app.post("/sessions/{session_id}/restart", status_code=201)
    def restart_session(
        session_id: str,
        request: RestartVirtualRecorderSessionRequest,
        manager: Annotated[VirtualRecorderSessionManager, Depends(get_manager)],
        registry: Annotated[BedRegistry, Depends(get_bed_registry)],
    ) -> dict[str, Any]:
        emit_testkit_event(
            "api.session.restart.requested",
            session_id=session_id,
            beds=len(request.bed_room_names),
        )
        try:
            registry.require_registered_room_names(request.bed_room_names)
            snapshot = manager.restart_session(
                session_id,
                bed_room_names=request.bed_room_names,
            )
        except BedAlreadyAssignedError as exc:
            emit_testkit_event(
                "api.session.restart.conflicted",
                level=logging.WARNING,
                session_id=session_id,
                beds=len(request.bed_room_names),
                error=str(exc),
            )
            raise HTTPException(status_code=409, detail=str(exc)) from exc
        except ValueError as exc:
            emit_testkit_event(
                "api.session.restart.rejected",
                level=logging.WARNING,
                session_id=session_id,
                beds=len(request.bed_room_names),
                error=str(exc),
            )
            raise HTTPException(status_code=400, detail=str(exc)) from exc
        if snapshot is None:
            emit_testkit_event(
                "api.session.restart.missing",
                level=logging.WARNING,
                session_id=session_id,
            )
            raise HTTPException(status_code=404, detail="session not found")

        emit_testkit_event(
            "api.session.restart.accepted",
            source_session_id=session_id,
            session_id=snapshot.session_id,
            state=snapshot.state.value,
        )
        return session_snapshot_to_document(snapshot)

    @app.delete("/sessions/{session_id}")
    def delete_session(
        session_id: str,
        manager: Annotated[VirtualRecorderSessionManager, Depends(get_manager)],
    ) -> dict[str, Any]:
        emit_testkit_event("api.session.delete.requested", session_id=session_id)
        snapshot = manager.delete_session(session_id)
        if snapshot is None:
            emit_testkit_event(
                "api.session.delete.missing",
                level=logging.WARNING,
                session_id=session_id,
            )
            raise HTTPException(status_code=404, detail="session not found")

        emit_testkit_event(
            "api.session.delete.accepted",
            session_id=snapshot.session_id,
            state=snapshot.state.value,
        )
        return session_snapshot_to_document(snapshot)

    return app


def elapsed_ms(started: float) -> int:
    """Return elapsed milliseconds since a perf-counter start."""

    return int((time.perf_counter() - started) * 1000)


def bed_to_document(bed: Bed) -> dict[str, str]:
    """Convert one test bed identity to API JSON."""

    return {
        "roomName": bed.room_name,
        "bedId": bed.bed_id,
    }
