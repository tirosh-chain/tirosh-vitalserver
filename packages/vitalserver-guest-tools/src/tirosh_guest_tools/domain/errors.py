from __future__ import annotations


class GuestToolsDomainError(Exception):
    def __init__(self, message: str, *, code: str) -> None:
        super().__init__(message)
        self.message = message
        self.code = code


class GuestContractError(GuestToolsDomainError, ValueError):
    pass


class GuestOperationRequestError(GuestToolsDomainError, ValueError):
    pass


class GuestUseCaseInputError(GuestToolsDomainError, ValueError):
    pass


class GuestDependencyError(GuestToolsDomainError, RuntimeError):
    pass
