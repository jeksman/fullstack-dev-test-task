"""The dependency rule, enforced instead of trusted.

`app.core.domain`, `app.core.ports` and `app.core.use_cases` are the inner
layers. They must not know about frameworks, the ORM, or the outer layers.
"""

import ast
from pathlib import Path

import pytest

CORE_PACKAGES = ("domain", "ports", "use_cases")
FORBIDDEN_PREFIXES = (
    "fastapi",
    "sqlmodel",
    "sqlalchemy",
    "pydantic",
    "requests",
    "jwt",
    "alembic",
    "app.models",
    "app.crud",
    "app.api",
    "app.infrastructure",
    "app.core.db",
    "app.core.config",
    "app.core.security",
)

CORE_ROOT = Path(__file__).resolve().parents[1] / "app" / "core"


def _core_modules() -> list[Path]:
    return sorted(
        path
        for package in CORE_PACKAGES
        for path in (CORE_ROOT / package).rglob("*.py")
    )


def _imported_names(tree: ast.AST) -> list[str]:
    names: list[str] = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            names.extend(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module and node.level == 0:
            names.append(node.module)
    return names


def test_core_packages_are_not_empty() -> None:
    assert _core_modules(), "architecture test found no core modules to check"


@pytest.mark.parametrize("module", _core_modules(), ids=lambda p: p.name)
def test_core_module_has_no_outward_imports(module: Path) -> None:
    tree = ast.parse(module.read_text())
    offenders = [
        name for name in _imported_names(tree) if name.startswith(FORBIDDEN_PREFIXES)
    ]
    assert not offenders, f"{module.name} imports outer-layer modules: {offenders}"
