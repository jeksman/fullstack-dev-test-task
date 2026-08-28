"""Integration tests for the HTTP surface: they check that the policy decision
reaches the client as the right status code, nothing more."""

from collections.abc import Callable

import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session

from app import crud
from app.core.config import settings
from app.core.domain.rbac import Permission, Role
from app.models import UserCreate
from tests.utils.user import user_authentication_headers
from tests.utils.utils import random_email, random_lower_string

HeadersFor = Callable[[Role], dict[str, str]]


@pytest.fixture(scope="module")
def headers_for(client: TestClient, db: Session) -> HeadersFor:
    """Log in as a freshly created user holding the given role."""

    def factory(role: Role) -> dict[str, str]:
        email, password = random_email(), random_lower_string()
        crud.create_user(
            session=db,
            user_create=UserCreate(email=email, password=password, role=role),
        )
        return user_authentication_headers(
            client=client, email=email, password=password
        )

    return factory


ALLOWED, DENIED = 200, 403

# Every protected endpoint is asserted for all three roles, so each row of the
# permission matrix has both an allowed and a denied case.
CASES = [
    ("GET", "/users/", Role.ADMIN, ALLOWED),
    ("GET", "/users/", Role.MANAGER, ALLOWED),
    ("GET", "/users/", Role.MEMBER, DENIED),
    ("GET", "/metrics/summary", Role.ADMIN, ALLOWED),
    ("GET", "/metrics/summary", Role.MANAGER, ALLOWED),
    ("GET", "/metrics/summary", Role.MEMBER, DENIED),
    ("GET", "/users/me", Role.ADMIN, ALLOWED),
    ("GET", "/users/me", Role.MANAGER, ALLOWED),
    ("GET", "/users/me", Role.MEMBER, ALLOWED),
]


@pytest.mark.parametrize(("method", "path", "role", "expected"), CASES)
def test_endpoint_enforces_the_permission_matrix(
    client: TestClient,
    headers_for: HeadersFor,
    method: str,
    path: str,
    role: Role,
    expected: int,
) -> None:
    response = client.request(
        method, f"{settings.API_V1_STR}{path}", headers=headers_for(role)
    )
    assert response.status_code == expected


@pytest.mark.parametrize(
    ("role", "expected"),
    [(Role.ADMIN, 200), (Role.MANAGER, 403), (Role.MEMBER, 403)],
)
def test_only_admin_can_create_users(
    client: TestClient, headers_for: HeadersFor, role: Role, expected: int
) -> None:
    response = client.post(
        f"{settings.API_V1_STR}/users/",
        headers=headers_for(role),
        json={"email": random_email(), "password": random_lower_string()},
    )
    assert response.status_code == expected


@pytest.mark.parametrize("role", list(Role))
def test_users_cannot_escalate_their_role_through_self_update(
    client: TestClient, headers_for: HeadersFor, role: Role
) -> None:
    headers = headers_for(role)

    response = client.patch(
        f"{settings.API_V1_STR}/users/me",
        headers=headers,
        json={"full_name": "Escalation attempt", "role": Role.ADMIN},
    )

    assert response.status_code == 200
    assert response.json()["role"] == role
    # The unknown field is ignored rather than applied — re-reading confirms it
    # was never persisted.
    me = client.get(f"{settings.API_V1_STR}/users/me", headers=headers)
    assert me.json()["role"] == role


def test_signup_cannot_choose_a_role(client: TestClient) -> None:
    response = client.post(
        f"{settings.API_V1_STR}/users/signup",
        json={
            "email": random_email(),
            "password": random_lower_string(),
            "role": Role.ADMIN,
        },
    )
    assert response.status_code == 200
    assert response.json()["role"] == Role.MEMBER


@pytest.mark.parametrize("role", list(Role))
def test_permissions_endpoint_reports_the_callers_own_capabilities(
    client: TestClient, headers_for: HeadersFor, role: Role
) -> None:
    response = client.get(
        f"{settings.API_V1_STR}/users/me/permissions", headers=headers_for(role)
    )

    assert response.status_code == 200
    granted = set(response.json())
    assert Permission.PROFILE_UPDATE_OWN in granted
    assert (Permission.USER_LIST in granted) is (role in (Role.ADMIN, Role.MANAGER))
    assert (Permission.USER_CREATE in granted) is (role is Role.ADMIN)


def test_denied_request_returns_403_not_an_empty_200(
    client: TestClient, headers_for: HeadersFor
) -> None:
    response = client.get(
        f"{settings.API_V1_STR}/users/", headers=headers_for(Role.MEMBER)
    )
    assert response.status_code == 403
    assert response.json()["detail"]
