"""FastAPI app for controlling TestKit virtual VRecorder sessions."""

from __future__ import annotations

from typing import Annotated, Any

from fastapi import Depends, FastAPI, HTTPException

from tirosh_vitalserver.testkit.adapters.outbound.recorder import connect_socketio
from tirosh_vitalserver.testkit.application.recorder_session import (
    VirtualRecorderSessionManager,
    session_snapshot_to_document,
)
from tirosh_vitalserver.testkit.schemas.testkit_api import StartVirtualRecordersRequest


def create_testkit_app(
    manager: VirtualRecorderSessionManager | None = None,
) -> FastAPI:
    """Build the TestKit FastAPI application."""

    app = FastAPI(
        title="VitalServer TestKit API",
        version="0.1.0",
    )
    session_manager = manager or VirtualRecorderSessionManager(
        connector=connect_socketio,
    )

    def get_manager() -> VirtualRecorderSessionManager:
        return session_manager

    ManagerDependency = Annotated[VirtualRecorderSessionManager, Depends(get_manager)]

    @app.get("/health")
    def health() -> dict[str, str]:
        return {"status": "ok"}

    @app.get("/sessions")
    def list_sessions(
        manager: ManagerDependency,
    ) -> dict[str, list[dict[str, Any]]]:
        return {
            "sessions": [
                session_snapshot_to_document(session)
                for session in manager.list_sessions()
            ]
        }

    @app.post("/sessions", status_code=201)
    def start_session(
        request: StartVirtualRecordersRequest,
        manager: ManagerDependency,
    ) -> dict[str, Any]:
        try:
            snapshot = manager.start_session(request.to_session_request())
        except ValueError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from exc

        return session_snapshot_to_document(snapshot)

    @app.get("/sessions/{session_id}")
    def get_session(
        session_id: str,
        manager: ManagerDependency,
    ) -> dict[str, Any]:
        snapshot = manager.get_session(session_id)
        if snapshot is None:
            raise HTTPException(status_code=404, detail="session not found")

        return session_snapshot_to_document(snapshot)

    @app.post("/sessions/{session_id}/stop")
    def stop_session(
        session_id: str,
        manager: ManagerDependency,
    ) -> dict[str, Any]:
        snapshot = manager.stop_session(session_id)
        if snapshot is None:
            raise HTTPException(status_code=404, detail="session not found")

        return session_snapshot_to_document(snapshot)

    return app
