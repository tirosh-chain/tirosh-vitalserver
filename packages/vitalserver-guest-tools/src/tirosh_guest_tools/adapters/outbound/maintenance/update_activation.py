from __future__ import annotations

from tirosh_guest_tools.application.update_activation import activate_runtime
from tirosh_guest_tools.domain.errors import GuestToolsDomainError
from tirosh_guest_tools.domain.guest_control.models import (
    UpdateActivationDependencyError,
    UpdateActivationResult,
)


class UpdateActivationMaintenanceAdapter:
    def activate_update(
        self,
        *,
        request_id: str,
        version: str,
    ) -> UpdateActivationResult:
        try:
            activate_runtime()
        except GuestToolsDomainError as error:
            raise UpdateActivationDependencyError(
                error.message,
                kind=error.code,
            ) from error
        except Exception as error:
            raise UpdateActivationDependencyError(
                f"Update activation failed: {error}",
                kind="update-activation-failed",
            ) from error
        return UpdateActivationResult(request_id=request_id, version=version)
