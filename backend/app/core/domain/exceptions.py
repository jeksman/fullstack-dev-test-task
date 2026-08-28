"""Domain-level failures. Controllers translate these into HTTP status codes;
the core itself knows nothing about HTTP."""


class DomainError(Exception):
    pass


class AccessDenied(DomainError):
    """The caller's role does not grant the required permission."""


class UserNotFound(DomainError):
    pass


class EmailAlreadyTaken(DomainError):
    pass
