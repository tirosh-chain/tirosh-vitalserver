from __future__ import annotations

from collections.abc import Callable
from threading import Thread

from tirosh_guest_tools.application.contexts import PrepareUpdateShutdownContext
from tirosh_guest_tools.application.update_shutdown import (
    request_guest_poweroff,
    run_prepare_until_poweroff_ready,
)
from tirosh_guest_tools.domain.errors import GuestToolsDomainError
from tirosh_guest_tools.domain.guest_control.models import (
    UpdateShutdownDependencyError,
    UpdateShutdownResult,
)


class UpdateShutdownMaintenanceAdapter:
    def prepare_update_shutdown(
        self,
        *,
        request_id: str,
        version: str,
        on_ready: Callable[[UpdateShutdownResult], None],
        on_failure: Callable[[UpdateShutdownDependencyError], None],
    ) -> None:
        thread = Thread(
            target=self._run_prepare,
            kwargs={
                "request_id": request_id,
                "version": version,
                "on_ready": on_ready,
                "on_failure": on_failure,
            },
            daemon=True,
        )
        thread.start()

    def _run_prepare(
        self,
        *,
        request_id: str,
        version: str,
        on_ready: Callable[[UpdateShutdownResult], None],
        on_failure: Callable[[UpdateShutdownDependencyError], None],
    ) -> None:
        context = PrepareUpdateShutdownContext(
            request_id=request_id,
            version=version,
        )
        try:
            run_prepare_until_poweroff_ready(
                context,
                on_poweroff_ready=lambda ready_context: on_ready(
                    UpdateShutdownResult(
                        request_id=ready_context.request_id,
                        version=ready_context.version,
                        shutdown_phase="poweroff-ready",
                        redis_backup_path=ready_context.redis_backup_path,
                    )
                ),
            )
        except GuestToolsDomainError as error:
            on_failure(
                UpdateShutdownDependencyError(
                    error.message,
                    kind=error.code,
                )
            )
        except Exception as error:
            on_failure(
                UpdateShutdownDependencyError(
                    f"Update shutdown failed: {error}",
                    kind="update-shutdown-failed",
                )
            )

    def request_poweroff(self) -> None:
        try:
            request_guest_poweroff()
        except GuestToolsDomainError as error:
            raise UpdateShutdownDependencyError(
                error.message,
                kind=error.code,
            ) from error
        except Exception as error:
            raise UpdateShutdownDependencyError(
                f"Guest poweroff request failed: {error}",
                kind="guest-poweroff-request-failed",
            ) from error
