from typing import Any

from fastapi import APIRouter, Depends
from sqlmodel import SQLModel, func, select

from app.api.deps import SessionDep, require
from app.core.domain.rbac import Permission
from app.models import Item, User

router = APIRouter(prefix="/metrics", tags=["metrics"])


class MetricsSummary(SQLModel):
    total_users: int
    active_users: int
    total_items: int


@router.get(
    "/summary",
    dependencies=[Depends(require(Permission.METRICS_VIEW))],
    response_model=MetricsSummary,
)
def read_metrics_summary(session: SessionDep) -> Any:
    """
    Aggregate counts for the insights page. Requires `metrics:view`
    (admin, manager).
    """
    return MetricsSummary(
        total_users=session.exec(select(func.count()).select_from(User)).one(),
        active_users=session.exec(
            select(func.count()).select_from(User).where(User.is_active)
        ).one(),
        total_items=session.exec(select(func.count()).select_from(Item)).one(),
    )
