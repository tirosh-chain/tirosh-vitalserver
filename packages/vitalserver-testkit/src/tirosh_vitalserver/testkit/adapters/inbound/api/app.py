"""FastAPI app for controlling TestKit virtual VRecorder sessions."""

from __future__ import annotations

import logging
import time
from typing import Annotated, Any

from fastapi import Depends, FastAPI, HTTPException, Request

from tirosh_vitalserver.testkit.adapters.outbound.recorder import connect_socketio
from tirosh_vitalserver.testkit.application.recorder_session import (
    VirtualRecorderSessionManager,
    session_snapshot_to_document,
)
from tirosh_vitalserver.testkit.observability import emit_testkit_event
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
        emit_testkit_event(
            "api.session.start.requested",
            target_url=request.target_url,
            recorders=request.recorders,
            vrcode=request.vrcode,
            interval_seconds=request.interval_seconds,
            duration_seconds=request.duration_seconds,
            max_messages=request.max_messages,
            default_scenario=request.default_scenario.value,
        )
        try:
            snapshot = manager.start_session(request.to_session_request())
        except ValueError as exc:
            emit_testkit_event(
                "api.session.start.rejected",
                level=logging.WARNING,
                target_url=request.target_url,
                recorders=request.recorders,
                error=str(exc),
            )
            raise HTTPException(status_code=400, detail=str(exc)) from exc

        emit_testkit_event(
            "api.session.start.accepted",
            session_id=snapshot.session_id,
            state=snapshot.state.value,
            target_url=snapshot.request.target_url,
            recorders=snapshot.request.recorders,
            vrcode=snapshot.request.vrcode,
        )
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

    return app


def elapsed_ms(started: float) -> int:
    """Return elapsed milliseconds since a perf-counter start."""

    return int((time.perf_counter() - started) * 1000)
