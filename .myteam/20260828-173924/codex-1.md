Reading additional input from stdin...
OpenAI Codex v0.149.1
--------
workdir: /Users/johndoe/Desktop/PERSONAL/test_tasks/Fullstack-Dev-Test-Task
model: gpt-5.6-sol
provider: openai
approval: never
sandbox: danger-full-access
reasoning effort: none
reasoning summaries: none
session id: 01a048cf-af16-74a0-b3f2-a6749638deef
--------
user
Задача: -n3 Fullstack-Dev-Test-Task
This is a task to test potential candidate skills in Python + SQL + TypeScript.

Assignment: Add Role-Aware Access + Architecture Decisions + Run the app
Timebox: Aim for up to 1 hour. If you cut scope, say what you cut and why.
Table of Contents
Goal
Base Template
Suggested Time Allocation
Requirements
1. Clone the Base Template
2. Roles and Authorization Surface
3. Code Quality Expectations
4. Architecture & Documentation
5. Non-Functional Requirements
6. UX Behavior
7. Developer UX
Constraints
What We Review
Submission
Goal
Add role-based access control (RBAC) to the existing Full-Stack FastAPI Template so that only authorized users can access sensitive endpoints and UI sections.

We prioritize clean, maintainable code over comprehensive test coverage or extensive documentation.

You may reuse any libraries already in the template.

Note: RBAC can be implemented with simple role checks or a small policy layer. Keep scope tight. Favor clarity over cleverness.

Base Template
Tech Stack:

Backend: FastAPI / SQLModel / PostgreSQL
Frontend: React / TypeScript
Repository: full-stack-fastapi-template

Suggested Time Allocation
How we believe it is doable in a 1-hour timebox:

Activity	Time	Priority
Understanding the codebase	15 min	High
Implementation (clear, maintainable code)	25 mins	Critical
Testing (focused, critical paths)	10 min	High
Documentation (README updates)	10 min	Medium
If running short on time:

✓ Prioritize: Clear, working authorization code with consistent patterns
✓ Then: 3-5 well-chosen tests covering critical scenarios
⚠ Cut if needed: Extra features, comprehensive test coverage, diagrams
❌ Don't cut: Security checks, README setup instructions
Requirements
1. Clone the Base Template
Clone the repository: https://github.com/fastapi/full-stack-fastapi-template/tree/master

2. Roles and Authorization Surface
Implement the Following Roles
Role	Permissions
admin	Full access to user management and settings
manager	Can list users and view metrics, but not change global settings
member	Can only access their own profile and basic app features
Protect a Small but Realistic Surface
List users
Create user
View metrics/insights page (simple stub is acceptable)
View and update own profile
Exact permission mapping is up to you.

State it clearly in your docs and enforce it consistently in the backend and frontend.

Example Permission Matrix (Document Something Similar)
Action	admin	manager	member
List all users	✓	✓	✗
Create user	✓	✗	✗
View metrics	✓	✓	✗
Update own profile	✓	✓	✓
Update any profile	✓	✗	✗
3. Code Quality Expectations
We prioritize maintainable, readable code over clever solutions.

Clear naming: Function/variable names that explain intent without comments
Single responsibility: Small, focused functions
Easy to extend: Adding a new role shouldn't require touching 10+ files
Self-documenting: Code structure makes the authorization model obvious
Key principle: A teammate should understand your authorization model in 5 minutes by reading your code.

4. Architecture & Documentation
Document your implementation approach clearly but concisely.

Required
 Permission matrix in README showing which role can access what
 Brief explanation (2-4 paragraphs) of your authorization approach:
Where authorization checks live (middleware, dependencies, decorators?)
How roles are stored and validated
How frontend learns about user capabilities
 Inline code comments only for non-obvious authorization logic
Optional (Bonus Points)
 1-2 Architecture Decision Records (ADRs) for your most critical decisions
Use any simple ADR format (problem, options, decision, trade-offs)
200-400 words each
Example topics: Why you chose your authorization pattern, where checks live, how the frontend handles permissions
 Simple diagram showing where auth/authz checks happen
Mermaid, C4-style, or hand-drawn PNG is fine
Philosophy: We value clear thinking over formal documentation. Your code should clearly explain your approach; that's usually sufficient. RBAC implementation, though, usually has at least a few options to implement, hence an additional README will add value.

5. Non-Functional Requirements
Demonstrate you considered real-world constraints:

1. Maintainability (Critical)
Keep coupling low; use consistent patterns
A teammate should understand your authorization logic in 5 minutes
2. Testability (Important)
Provide focused backend tests covering critical authorization paths
Note: Tests are required, but we prioritize quality over quantity. 3 well-chosen tests with clean code beat 20 tests with spaghetti code.

3. UX Behavior
The UI should:
Hide navigation links/buttons that the user can't access
Show a friendly Forbidden or Access Denied message if navigating directly to unauthorized routes
Not just fail silently or show cryptic errors
4. Developer UX
Update the README with:

How to run locally (setup, dependencies, database)
How to seed test data with at least one admin and one non-admin user
How to run tests
Database migrations for any schema changes (if applicable)
Make it easy for us to run your solution without hunting for setup instructions.

What We Review
Primary Criteria (60%)
Code readability and maintainability

✓ Clear separation of concerns
✓ Consistent authorization patterns
✓ Self-documenting code structure
✓ Low coupling between components
✓ Easy to understand and extend
Working RBAC implementation

✓ Consistent enforcement in backend and frontend
✓ No obvious security gaps or privilege escalation
✓ Correct HTTP status codes and error handling
Secondary Criteria (30%)
Test coverage

✓ Focused tests on critical authorization paths
✓ Both allowed and denied scenarios tested
✓ Tests are clear and well-named
Setup and documentation

✓ Setup instructions work on first try
✓ Clear explanation of authorization approach
✓ Permission matrix documented
Nice to Have (10%)
Thoughtful UX for forbidden states
Observability (logging denied attempts)
Architecture Decision Records (ADRs)
Helpful diagrams
Extra polish
Philosophy: We're evaluating your ability to write production-quality code under time constraints. We'd rather hire someone who delivers clean, working code with good tests than someone who delivers everything but it's hard to maintain.

Submission
Deliverables:

 PR or repo link with commit history
 Updated README with:
Setup instructions
Permission matrix
Brief explanation of your approach
 Backend tests covering critical authorization scenarios
 Working implementation of RBAC
 Optional: NOTES.md with anything you want us to know (scope cuts, trade-offs, what you'd do with more time)
after verify, test and run - commit & push it to https://github.com/jeksman/fullstack-dev-test-task, use guidelines inside the folder you do it

Предложи решение: что именно менять и почему. Назови главный риск своего подхода. Отвечай по-русски, коротко и по делу. Файлы не изменяй — сейчас идёт разбор, а не реализация. Читать код можно и нужно.
codex
Отвечу как архитектор full-stack систем на FastAPI/PostgreSQL/React, лауреат Ukrainian IT Awards в категории Software Architecture.

Сначала прочитаю локальные инструкции и текущую структуру проекта, затем сверю существующие модели, API, маршруты фронтенда, тесты и документацию. Файлы менять, коммитить и отправлять не буду: сейчас только разбор решения.
exec
/bin/zsh -lc "pwd && rg --files -g 'AGENTS.md' -g '"'!node_modules'"' -g '"'!frontend/node_modules'"' -g '"'!backend/.venv'"' | sort && rg --files -g '"'!node_modules'"' -g '"'!frontend/node_modules'"' -g '"'!backend/.venv'"' | sed -n '1,240p'" in /Users/johndoe/Desktop/PERSONAL/test_tasks/Fullstack-Dev-Test-Task
 succeeded in 0ms:
/Users/johndoe/Desktop/PERSONAL/test_tasks/Fullstack-Dev-Test-Task
CLAUDE.md
README.md
chat-history/2026-08-28.md

exec
/bin/zsh -lc "ls -la && sed -n '1,260p' CLAUDE.md && sed -n '1,280p' README.md && git status --short --branch && git remote -v" in /Users/johndoe/Desktop/PERSONAL/test_tasks/Fullstack-Dev-Test-Task
 succeeded in 0ms:
total 40
drwxr-xr-x   7 johndoe  staff   224 Aug 28 17:31 .
drwxr-xr-x@  7 johndoe  staff   224 Aug 28 17:20 ..
drwxr-xr-x  12 johndoe  staff   384 Aug 28 17:38 .git
drwxr-xr-x@  5 johndoe  staff   160 Aug 28 17:39 .myteam
-rw-r--r--@  1 johndoe  staff  8498 Aug 28 17:31 CLAUDE.md
-rw-r--r--   1 johndoe  staff  8071 Aug 28 17:20 README.md
drwxr-xr-x@  3 johndoe  staff    96 Aug 28 17:28 chat-history
# Архитектурные гайдлайны проекта

RBAC поверх `full-stack-fastapi-template` (FastAPI / SQLModel / PostgreSQL / React+TS),
построенный по Clean Architecture. Правила ниже обязательны для любого кода в этом репозитории.

## 1. Слои и направление зависимостей

Зависимости направлены строго ВНУТРЬ. Внешний слой знает о внутреннем, внутренний о внешнем — никогда.

```
Infrastructure  ->  Adapters  ->  Use Cases  ->  Entities
   (L4)              (L3)          (L2)           (L1)
```

| Слой | Каталог | Что содержит | Что разрешено импортировать |
|------|---------|--------------|------------------------------|
| **L1 Entities** | `backend/app/core/domain/` | Бизнес-объекты и правила: `Role`, `Permission`, `ROLE_PERMISSIONS`, `User` как `@dataclass`. Валидация инвариантов. | Только stdlib |
| **L2 Use Cases** | `backend/app/core/use_cases/`, порты в `backend/app/core/ports/` | Сценарии: `ListUsersUseCase`, `CreateUserUseCase`, `UpdateOwnProfileUseCase`, `AuthorizationPolicy`. Абстрактные интерфейсы (`ABC`). | stdlib + L1 |
| **L3 Adapters** | `backend/app/api/` (routes, deps), `backend/app/infrastructure/repositories/` | Контроллеры FastAPI, DI-провайдеры, реализации портов, мапперы ORM ↔ Entity, presenters. | stdlib + L1 + L2 + фреймворки |
| **L4 Infrastructure** | `backend/app/models.py`, `core/db.py`, `alembic/`, `frontend/` | SQLModel-таблицы, движок БД, миграции, конфиг, React. | что угодно |

Границы модуля `app/core/` — священны: **всё, что лежит внутри `app/core/domain/`,
`app/core/ports/` и `app/core/use_cases/`, не содержит ни одного импорта**
`fastapi`, `sqlmodel`, `sqlalchemy`, `pydantic`, `requests`, `jwt`, `app.models`, `app.crud`.

Проверка этого правила — исполняемая, а не на честном слове: тест
`backend/tests/test_architecture.py` обходит AST всех модулей ядра и падает
на запрещённом импорте. Он часть критических путей, удалять его нельзя.

## 2. Инверсия зависимостей (DIP)

- Порт (`ABC`) объявляется в `app/core/ports/`, рядом с тем, кто его потребляет, — не рядом с реализацией.
- Реализация живёт в `app/infrastructure/repositories/` и наследует порт явно.
- Зависимости передаются **только через `__init__`**. Никаких глобальных синглтонов,
  импортов конкретных реализаций внутри use case и обращений к `Depends()` в ядре.

```python
# app/core/ports/user_repository.py                     (L2)
class AbstractUserRepository(ABC):
    @abstractmethod
    def list(self, *, skip: int, limit: int) -> tuple[list[User], int]: ...

# app/infrastructure/repositories/sqlmodel_user_repository.py   (L3)
class SQLModelUserRepository(AbstractUserRepository): ...

# app/core/use_cases/list_users.py                      (L2)
class ListUsersUseCase:
    def __init__(self, users: AbstractUserRepository, policy: AuthorizationPolicy) -> None: ...
```

Сборка графа зависимостей — единственное место, где встречаются абстракция и реализация:
`app/api/deps.py`. Это composition root.

## 3. DTO и запрет на протечку моделей

- SQLModel-таблицы (`app.models.User`), Pydantic-схемы запросов и ответов
  **не пересекают границу L3 → L2**. Никогда.
- На границе работает маппер: `to_entity(db_user) -> User`, `to_public(user) -> UserPublic`.
  Мапперы живут в L3 (`app/infrastructure/mappers.py`), потому что знают про обе стороны.
- Внутрь use case входят и наружу выходят только dataclass-и из L1 и примитивы.
- Use case не возвращает HTTP-статусы и не поднимает `HTTPException` — он поднимает
  доменные исключения (`AccessDenied`, `UserNotFound`), а контроллер переводит их в коды ответа.

## 4. Чистый код

- Type hints обязательны для всех сигнатур и полей. Без `Any` там, где тип известен.
- Один класс / одна функция — одна причина для изменения (SRP).
  `AuthorizationPolicy` только решает «можно ли», репозиторий только достаёт данные,
  контроллер только транслирует HTTP.
- Имена объясняют намерение: `require(Permission.USER_LIST)`, а не `check_perm(3)`.
- Комментарии — только для неочевидной логики авторизации. Остальное объясняет структура.
- Добавление новой роли обязано сводиться к одной строке в `ROLE_PERMISSIONS`
  и нигде больше. Если пришлось трогать больше — модель ролей спроектирована неверно.

## 5. Тестируемость

- Use case тестируется без БД, без HTTP и без Docker: в конструктор подаётся
  in-memory фейк порта или `unittest.mock.Mock(spec=AbstractUserRepository)`.
- `AuthorizationPolicy` — чистая функция от `(Role, Permission)`, мокать в ней нечего.
- Интеграционные тесты через `TestClient` покрывают только трансляцию: 200 против 403.
- Каждый защищённый эндпоинт проверяется в обоих сценариях — разрешено и запрещено.

## 6. Инварианты авторизации (security)

Эти правила не упрощаются и не срезаются ради краткости:

- Backend — единственный источник истины. Фронтенд скрывает кнопки ради UX,
  но никогда не является средством контроля доступа.
- Фронтенд узнаёт о своих правах из `GET /api/v1/users/me/permissions`,
  а не из захардкоженного списка ролей в TS.
- Проверка прав выполняется до любого побочного эффекта и до чтения чувствительных данных.
- Отказ — это `403 Forbidden` с внятным сообщением; отсутствующий объект — `404`.
  Отказ не маскируется под `200` с пустым телом.
- Эскалация привилегий закрыта явно: пользователь не может назначить себе роль
  выше собственной, в том числе через `PATCH /users/me`.
- Каждый отказ логируется (кто, какое разрешение, какой ресурс).

## 7. Технические факты о шаблоне

- Требуется **Python ≥ 3.14**: в `app/api/deps.py` используется `except A, B:` без скобок (PEP 758).
- Пакетный менеджер backend — `uv`, frontend — `bun`.
- Существующая модель прав в шаблоне — булев флаг `is_superuser`. Он остаётся в БД
  ради совместимости миграций, но новым источником истины становится колонка `role`.

## 8. Ведение истории

Каждая сессия дописывает запись в `chat-history/ГГГГ-ММ-ДД.md`: что просили, что сделано.
# Fullstack-Dev-Test-Task

This is a task to test potential candidate skills in Python + SQL + TypeScript.

- **Assignment**: Add Role-Aware Access + Architecture Decisions + **Run the app**
- **Timebox**: Aim for up to 1 hour. If you cut scope, say what you cut and why.


## Table of Contents

- [Goal](#goal)
- [Base Template](#base-template)
- [Suggested Time Allocation](#suggested-time-allocation)
- [Requirements](#requirements)
  - [1. Clone the Base Template](#1-clone-the-base-template)
  - [2. Roles and Authorization Surface](#2-roles-and-authorization-surface)
  - [3. Code Quality Expectations](#3-code-quality-expectations)
  - [4. Architecture & Documentation](#4-architecture--documentation)
  - [5. Non-Functional Requirements](#5-non-functional-requirements)
  - [6. UX Behavior](#6-ux-behavior)
  - [7. Developer UX](#7-developer-ux)
- [Constraints](#constraints)
- [What We Review](#what-we-review)
- [Submission](#submission)

## Goal

Add role-based access control (RBAC) to the existing Full-Stack FastAPI Template so that only authorized users can access sensitive endpoints and UI sections.

**We prioritize clean, maintainable code over comprehensive test coverage or extensive documentation.**

You may reuse any libraries already in the template.

> **Note**: RBAC can be implemented with simple role checks or a small policy layer. Keep scope tight. Favor clarity over cleverness.

## Base Template

**Tech Stack**:
- **Backend**: FastAPI / SQLModel / PostgreSQL
- **Frontend**: React / TypeScript

**Repository**: [full-stack-fastapi-template](https://github.com/fastapi/full-stack-fastapi-template/tree/master)

## Suggested Time Allocation

How we believe it is doable in a 1-hour timebox:

| Activity | Time           | Priority |
|----------|----------------|----------|
| Understanding the codebase | 15 min         | High |
| Implementation (clear, maintainable code) | 25 mins | **Critical** |
| Testing (focused, critical paths) | 10 min         | High |
| Documentation (README updates) | 10 min         | Medium |

**If running short on time:**
- ✓ **Prioritize**: Clear, working authorization code with consistent patterns
- ✓ **Then**: 3-5 well-chosen tests covering critical scenarios
- ⚠ **Cut if needed**: Extra features, comprehensive test coverage, diagrams
- ❌ **Don't cut**: Security checks, README setup instructions

## Requirements

### 1. Clone the Base Template

Clone the repository: https://github.com/fastapi/full-stack-fastapi-template/tree/master

### 2. Roles and Authorization Surface

#### Implement the Following Roles

| Role | Permissions |
|------|-------------|
| **admin** | Full access to user management and settings |
| **manager** | Can list users and view metrics, but not change global settings |
| **member** | Can only access their own profile and basic app features |

#### Protect a Small but Realistic Surface

- List users
- Create user
- View "metrics/insights" page (simple stub is acceptable)
- View and update own profile

**Exact permission mapping is up to you.**

State it clearly in your docs and enforce it consistently in the backend and frontend.

#### Example Permission Matrix (Document Something Similar)

| Action | admin | manager | member |
|--------|-------|---------|--------|
| List all users | ✓ | ✓ | ✗ |
| Create user | ✓ | ✗ | ✗ |
| View metrics | ✓ | ✓ | ✗ |
| Update own profile | ✓ | ✓ | ✓ |
| Update any profile | ✓ | ✗ | ✗ |

### 3. Code Quality Expectations

**We prioritize maintainable, readable code over clever solutions.**
 
- **Clear naming**: Function/variable names that explain intent without comments
- **Single responsibility**: Small, focused functions
- **Easy to extend**: Adding a new role shouldn't require touching 10+ files
- **Self-documenting**: Code structure makes the authorization model obvious

> **Key principle**: A teammate should understand your authorization model in 5 minutes by reading your code.

### 4. Architecture & Documentation

Document your implementation approach clearly but concisely.

#### Required

- [ ] **Permission matrix** in README showing which role can access what
- [ ] **Brief explanation** (2-4 paragraphs) of your authorization approach:
  - Where authorization checks live (middleware, dependencies, decorators?)
  - How roles are stored and validated
  - How frontend learns about user capabilities
- [ ] **Inline code comments** only for non-obvious authorization logic

#### Optional (Bonus Points)

- [ ] **1-2 Architecture Decision Records (ADRs)** for your most critical decisions
  - Use any simple ADR format (problem, options, decision, trade-offs)
  - 200-400 words each
  - Example topics: Why you chose your authorization pattern, where checks live, how the frontend handles permissions
- [ ] **Simple diagram** showing where auth/authz checks happen
  - Mermaid, C4-style, or hand-drawn PNG is fine

**Philosophy**: We value clear thinking over formal documentation. 
Your code should clearly explain your approach; that's usually sufficient.
RBAC implementation, though, usually has at least a few options to implement, hence an additional README will add value.

### 5. Non-Functional Requirements

Demonstrate you considered real-world constraints:

#### 1. Maintainability (Critical)

- Keep coupling low; use consistent patterns
- A teammate should understand your authorization logic in 5 minutes

#### 2. Testability (Important)

- Provide **focused backend tests** covering critical authorization paths

> **Note**: Tests are required, but we prioritize **quality over quantity**. 3 well-chosen tests with clean code beat 20 tests with spaghetti code.

### 3. UX Behavior

- **The UI** should:
  - Hide navigation links/buttons that the user can't access
  - Show a friendly "Forbidden" or "Access Denied" message if navigating directly to unauthorized routes
  - Not just fail silently or show cryptic errors

### 4. Developer UX

Update the README with:

- **How to run locally** (setup, dependencies, database)
- **How to seed test data** with at least one admin and one non-admin user
- **How to run tests**
- **Database migrations** for any schema changes (if applicable)

Make it easy for us to run your solution without hunting for setup instructions.

## What We Review

### Primary Criteria (60%)

**Code readability and maintainability**
- ✓ Clear separation of concerns
- ✓ Consistent authorization patterns
- ✓ Self-documenting code structure
- ✓ Low coupling between components
- ✓ Easy to understand and extend

**Working RBAC implementation**
- ✓ Consistent enforcement in backend and frontend
- ✓ No obvious security gaps or privilege escalation
- ✓ Correct HTTP status codes and error handling

### Secondary Criteria (30%)

**Test coverage**
- ✓ Focused tests on critical authorization paths
- ✓ Both allowed and denied scenarios tested
- ✓ Tests are clear and well-named

**Setup and documentation**
- ✓ Setup instructions work on first try
- ✓ Clear explanation of authorization approach
- ✓ Permission matrix documented

### Nice to Have (10%)

- Thoughtful UX for forbidden states
- Observability (logging denied attempts)
- Architecture Decision Records (ADRs)
- Helpful diagrams
- Extra polish

> **Philosophy**: We're evaluating your ability to write production-quality code under time constraints. We'd rather hire someone who delivers clean, working code with good tests than someone who delivers everything but it's hard to maintain.

## Submission

**Deliverables**:

- [ ] PR or repo link with commit history
- [ ] Updated README with:
  - Setup instructions
  - Permission matrix
  - Brief explanation of your approach
- [ ] Backend tests covering critical authorization scenarios
- [ ] Working implementation of RBAC
- [ ] Optional: `NOTES.md` with anything you want us to know (scope cuts, trade-offs, what you'd do with more time)

---

**Good luck!** Focus on demonstrating clear thinking and solid engineering fundamentals. We're looking for maintainable code, not perfect code.
## main...origin/main
?? .myteam/
?? CLAUDE.md
?? chat-history/
origin	git@github.com:evios/Fullstack-Dev-Test-Task.git (fetch)
origin	git@github.com:evios/Fullstack-Dev-Test-Task.git (push)

codex
В рабочей копии обнаружено важное расхождение: кода шаблона пока нет — только текст задания и `CLAUDE.md`; текущий `origin` указывает на `evios/Fullstack-Dev-Test-Task`, а не на целевой `jeksman/fullstack-dev-test-task`. Проверю историю/ветки и актуальную структуру upstream без изменения рабочей директории, чтобы план опирался на реальные точки расширения.
exec
/bin/zsh -lc "git log --oneline --decorate --graph --all -20 && git branch -a && git ls-tree -r --name-only HEAD | sed -n '1,240p' && git ls-remote --heads https://github.com/jeksman/fullstack-dev-test-task.git && git ls-remote --heads https://github.com/fastapi/full-stack-fastapi-template.git | sed -n '1,40p'" in /Users/johndoe/Desktop/PERSONAL/test_tasks/Fullstack-Dev-Test-Task
 succeeded in 1175ms:
698bdfcc2ad3e1030001611f4d1d8218d7c20144	refs/heads/fix-backend-reload-during-playwright-tests
486f054cc8d1aead59ec96cc0a16933d06c10e0d	refs/heads/master

web search: 
web search: https://github.com/fastapi/full-stack-fastapi-template/tree/master
exec
/bin/zsh -lc "curl -fsSL https://api.github.com/repos/fastapi/full-stack-fastapi-template/git/trees/master?recursive=1 | jq -r '.tree[].path' | rg '"'^(backend/app|backend/tests|frontend/src|backend/app/alembic|README|docker-compose|pyproject|package.json)'"' | sed -n '1,320p'" in /Users/johndoe/Desktop/PERSONAL/test_tasks/Fullstack-Dev-Test-Task
 succeeded in 0ms:
zsh:1: no matches found: https://api.github.com/repos/fastapi/full-stack-fastapi-template/git/trees/master?recursive=1

exec
/bin/zsh -lc "curl -fsSL 'https://api.github.com/repos/fastapi/full-stack-fastapi-template/git/trees/master?recursive=1' | jq -r '.tree[].path' | rg '"'^(backend/app|backend/tests|frontend/src|README|docker-compose|pyproject|package.json)'"' | sed -n '1,360p'" in /Users/johndoe/Desktop/PERSONAL/test_tasks/Fullstack-Dev-Test-Task
 succeeded in 266ms:
README.md
backend/app
backend/app/__init__.py
backend/app/alembic
backend/app/alembic/README
backend/app/alembic/env.py
backend/app/alembic/script.py.mako
backend/app/alembic/versions
backend/app/alembic/versions/.keep
backend/app/alembic/versions/1a31ce608336_add_cascade_delete_relationships.py
backend/app/alembic/versions/9c0a54914c78_add_max_length_for_string_varchar_.py
backend/app/alembic/versions/d98dd8ec85a3_edit_replace_id_integers_in_all_models_.py
backend/app/alembic/versions/e2412789c190_initialize_models.py
backend/app/alembic/versions/fe56fa70289e_add_created_at_to_user_and_item.py
backend/app/api
backend/app/api/__init__.py
backend/app/api/deps.py
backend/app/api/main.py
backend/app/api/routes
backend/app/api/routes/__init__.py
backend/app/api/routes/items.py
backend/app/api/routes/login.py
backend/app/api/routes/private.py
backend/app/api/routes/users.py
backend/app/api/routes/utils.py
backend/app/core
backend/app/core/__init__.py
backend/app/core/config.py
backend/app/core/db.py
backend/app/core/security.py
backend/app/crud.py
backend/app/email-templates
backend/app/email-templates/new_account.html
backend/app/email-templates/reset_password.html
backend/app/email-templates/test_email.html
backend/app/initial_data.py
backend/app/main.py
backend/app/models.py
backend/app/utils.py
backend/tests
backend/tests/__init__.py
backend/tests/api
backend/tests/api/__init__.py
backend/tests/api/routes
backend/tests/api/routes/__init__.py
backend/tests/api/routes/test_items.py
backend/tests/api/routes/test_login.py
backend/tests/api/routes/test_private.py
backend/tests/api/routes/test_users.py
backend/tests/conftest.py
backend/tests/crud
backend/tests/crud/__init__.py
backend/tests/crud/test_user.py
backend/tests/scripts
backend/tests/scripts/__init__.py
backend/tests/utils
backend/tests/utils/__init__.py
backend/tests/utils/item.py
backend/tests/utils/user.py
backend/tests/utils/utils.py
frontend/src
frontend/src/client
frontend/src/client/client.gen.ts
frontend/src/client/client
frontend/src/client/client/client.gen.ts
frontend/src/client/client/index.ts
frontend/src/client/client/types.gen.ts
frontend/src/client/client/utils.gen.ts
frontend/src/client/core
frontend/src/client/core/auth.gen.ts
frontend/src/client/core/bodySerializer.gen.ts
frontend/src/client/core/params.gen.ts
frontend/src/client/core/pathSerializer.gen.ts
frontend/src/client/core/queryKeySerializer.gen.ts
frontend/src/client/core/serverSentEvents.gen.ts
frontend/src/client/core/types.gen.ts
frontend/src/client/core/utils.gen.ts
frontend/src/client/index.ts
frontend/src/client/sdk.gen.ts
frontend/src/client/types.gen.ts
frontend/src/components
frontend/src/components/Admin
frontend/src/components/Admin/AddUser.tsx
frontend/src/components/Admin/DeleteUser.tsx
frontend/src/components/Admin/EditUser.tsx
frontend/src/components/Admin/UserActionsMenu.tsx
frontend/src/components/Admin/columns.tsx
frontend/src/components/Common
frontend/src/components/Common/Appearance.tsx
frontend/src/components/Common/AuthLayout.tsx
frontend/src/components/Common/DataTable.tsx
frontend/src/components/Common/ErrorComponent.tsx
frontend/src/components/Common/Footer.tsx
frontend/src/components/Common/Logo.tsx
frontend/src/components/Common/NotFound.tsx
frontend/src/components/Items
frontend/src/components/Items/AddItem.tsx
frontend/src/components/Items/DeleteItem.tsx
frontend/src/components/Items/EditItem.tsx
frontend/src/components/Items/ItemActionsMenu.tsx
frontend/src/components/Items/columns.tsx
frontend/src/components/Pending
frontend/src/components/Pending/PendingItems.tsx
frontend/src/components/Pending/PendingUsers.tsx
frontend/src/components/Sidebar
frontend/src/components/Sidebar/AppSidebar.tsx
frontend/src/components/Sidebar/Main.tsx
frontend/src/components/Sidebar/User.tsx
frontend/src/components/UserSettings
frontend/src/components/UserSettings/ChangePassword.tsx
frontend/src/components/UserSettings/DeleteAccount.tsx
frontend/src/components/UserSettings/DeleteConfirmation.tsx
frontend/src/components/UserSettings/UserInformation.tsx
frontend/src/components/theme-provider.tsx
frontend/src/components/ui
frontend/src/components/ui/alert.tsx
frontend/src/components/ui/avatar.tsx
frontend/src/components/ui/badge.tsx
frontend/src/components/ui/button-group.tsx
frontend/src/components/ui/button.tsx
frontend/src/components/ui/card.tsx
frontend/src/components/ui/checkbox.tsx
frontend/src/components/ui/dialog.tsx
frontend/src/components/ui/dropdown-menu.tsx
frontend/src/components/ui/form.tsx
frontend/src/components/ui/input.tsx
frontend/src/components/ui/label.tsx
frontend/src/components/ui/loading-button.tsx
frontend/src/components/ui/pagination.tsx
frontend/src/components/ui/password-input.tsx
frontend/src/components/ui/select.tsx
frontend/src/components/ui/separator.tsx
frontend/src/components/ui/sheet.tsx
frontend/src/components/ui/sidebar.tsx
frontend/src/components/ui/skeleton.tsx
frontend/src/components/ui/sonner.tsx
frontend/src/components/ui/table.tsx
frontend/src/components/ui/tabs.tsx
frontend/src/components/ui/tooltip.tsx
frontend/src/hooks
frontend/src/hooks/useAuth.ts
frontend/src/hooks/useCopyToClipboard.ts
frontend/src/hooks/useCustomToast.ts
frontend/src/hooks/useMobile.ts
frontend/src/index.css
frontend/src/lib
frontend/src/lib/utils.ts
frontend/src/main.tsx
frontend/src/routeTree.gen.ts
frontend/src/routes
frontend/src/routes/__root.tsx
frontend/src/routes/_layout.tsx
frontend/src/routes/_layout
frontend/src/routes/_layout/admin.tsx
frontend/src/routes/_layout/index.tsx
frontend/src/routes/_layout/items.tsx
frontend/src/routes/_layout/settings.tsx
frontend/src/routes/login.tsx
frontend/src/routes/recover-password.tsx
frontend/src/routes/reset-password.tsx
frontend/src/routes/signup.tsx
frontend/src/utils.ts
frontend/src/vite-env.d.ts
package.json
pyproject.toml

exec
/bin/zsh -lc "curl -fsSL 'https://raw.githubusercontent.com/fastapi/full-stack-fastapi-template/master/backend/app/core/db.py'
curl -fsSL 'https://raw.githubusercontent.com/fastapi/full-stack-fastapi-template/master/backend/app/initial_data.py'
curl -fsSL 'https://raw.githubusercontent.com/fastapi/full-stack-fastapi-template/master/backend/tests/api/routes/test_users.py'
curl -fsSL 'https://raw.githubusercontent.com/fastapi/full-stack-fastapi-template/master/backend/tests/conftest.py'" in /Users/johndoe/Desktop/PERSONAL/test_tasks/Fullstack-Dev-Test-Task
exec
/bin/zsh -lc "curl -fsSL 'https://raw.githubusercontent.com/fastapi/full-stack-fastapi-template/master/backend/app/models.py'
curl -fsSL 'https://raw.githubusercontent.com/fastapi/full-stack-fastapi-template/master/backend/app/api/deps.py'
curl -fsSL 'https://raw.githubusercontent.com/fastapi/full-stack-fastapi-template/master/backend/app/api/routes/users.py'
curl -fsSL 'https://raw.githubusercontent.com/fastapi/full-stack-fastapi-template/master/backend/app/api/main.py'" in /Users/johndoe/Desktop/PERSONAL/test_tasks/Fullstack-Dev-Test-Task
exec
/bin/zsh -lc "curl -fsSL 'https://raw.githubusercontent.com/fastapi/full-stack-fastapi-template/master/frontend/src/hooks/useAuth.ts'
curl -fsSL 'https://raw.githubusercontent.com/fastapi/full-stack-fastapi-template/master/frontend/src/routes/_layout.tsx'
curl -fsSL 'https://raw.githubusercontent.com/fastapi/full-stack-fastapi-template/master/frontend/src/routes/_layout/admin.tsx'
curl -fsSL 'https://raw.githubusercontent.com/fastapi/full-stack-fastapi-template/master/frontend/src/components/Sidebar/AppSidebar.tsx'" in /Users/johndoe/Desktop/PERSONAL/test_tasks/Fullstack-Dev-Test-Task
exec
/bin/zsh -lc "curl -fsSL 'https://raw.githubusercontent.com/fastapi/full-stack-fastapi-template/master/backend/pyproject.toml'
curl -fsSL 'https://raw.githubusercontent.com/fastapi/full-stack-fastapi-template/master/frontend/package.json'
curl -fsSL 'https://raw.githubusercontent.com/fastapi/full-stack-fastapi-template/master/docker-compose.yml'
curl -fsSL 'https://raw.githubusercontent.com/fastapi/full-stack-fastapi-template/master/README.md'" in /Users/johndoe/Desktop/PERSONAL/test_tasks/Fullstack-Dev-Test-Task
 succeeded in 999ms:
[project]
name = "app"
version = "0.1.0"
description = ""
requires-python = ">=3.14,<4.0"
dependencies = [
    "fastapi[standard]>=0.141.1,<1.0.0",
    "python-multipart<1.0.0,>=0.0.27",
    "email-validator<3.0.0.0,>=2.1.0.post1",
    "pydantic>2.0",
    "emails>=1.1.2,<2.0",
    "jinja2<4.0.0,>=3.1.4",
    "alembic<2.0.0,>=1.12.1",
    "httpx<1.0.0,>=0.25.1",
    "psycopg[binary]>=3.3.4,<4.0.0",
    "sqlmodel>=0.0.39,<1.0.0",
    "pydantic-settings<3.0.0,>=2.2.1",
    "sentry-sdk[fastapi]>=2.66.1,<3.0.0",
    "pyjwt<3.0.0,>=2.13.0",
    "pwdlib[argon2,bcrypt]>=0.3.0",
]

[dependency-groups]
dev = [
    "pytest<10.0.0,>=7.4.3",
    "mypy<3.0.0,>=1.8.0",
    "ty>=0.0.25",
    "ruff<1.0.0,>=0.2.2",
    "coverage<8.0.0,>=7.4.3",
]

[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[tool.mypy]
strict = true
exclude = ["venv", ".venv", "alembic"]

[tool.ruff]
target-version = "py314"
exclude = ["alembic"]

[tool.ruff.lint]
select = [
    "E",  # pycodestyle errors
    "W",  # pycodestyle warnings
    "F",  # pyflakes
    "I",  # isort
    "B",  # flake8-bugbear
    "C4",  # flake8-comprehensions
    "UP",  # pyupgrade
    "ARG001", # unused arguments in functions
    "T201",   # print statements are not allowed
]
ignore = [
    "E501",  # line too long, handled by black
    "B008",  # do not perform function calls in argument defaults
    "W191",  # indentation contains tabs
    "B904",  # Allow raising exceptions without from e, for HTTPException
]

[tool.ruff.lint.pyupgrade]
# Preserve types, even if a file imports `from __future__ import annotations`.
keep-runtime-typing = true

[tool.coverage.run]
source = ["app"]
dynamic_context = "test_function"

[tool.coverage.report]
show_missing = true
sort = "-Cover"

[tool.coverage.html]
show_contexts = true

[tool.ty.terminal]
error-on-warning = true

[tool.fastapi]
entrypoint = "app.main:app"
{
  "name": "frontend",
  "private": true,
  "version": "0.0.0",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc -p tsconfig.build.json && vite build",
    "lint": "biome check --write --unsafe --no-errors-on-unmatched --files-ignore-unknown=true ./",
    "preview": "vite preview",
    "generate-client": "openapi-ts",
    "test": "bunx playwright test",
    "test:ui": "bunx playwright test --ui"
  },
  "dependencies": {
    "@hookform/resolvers": "^5.7.1",
    "@radix-ui/react-avatar": "^1.2.6",
    "@radix-ui/react-checkbox": "^1.3.11",
    "@radix-ui/react-dialog": "^1.1.23",
    "@radix-ui/react-dropdown-menu": "^2.1.24",
    "@radix-ui/react-label": "^2.1.15",
    "@radix-ui/react-radio-group": "^1.4.7",
    "@radix-ui/react-scroll-area": "^1.2.18",
    "@radix-ui/react-select": "^2.3.7",
    "@radix-ui/react-separator": "^1.1.15",
    "@radix-ui/react-slot": "^1.2.4",
    "@radix-ui/react-tabs": "^1.1.21",
    "@radix-ui/react-tooltip": "^1.2.16",
    "@tailwindcss/vite": "^4.3.3",
    "@tanstack/react-query": "^5.101.4",
    "@tanstack/react-query-devtools": "^5.101.4",
    "@tanstack/react-router": "^1.170.18",
    "@tanstack/react-router-devtools": "^1.167.0",
    "@tanstack/react-table": "^8.21.3",
    "axios": "1.18.0",
    "class-variance-authority": "^0.7.1",
    "clsx": "^2.1.1",
    "form-data": "4.0.6",
    "lucide-react": "^1.28.0",
    "react": "^19.2.8",
    "react-dom": "^19.2.8",
    "react-error-boundary": "^6.1.2",
    "react-hook-form": "^7.84.0",
    "react-icons": "^5.7.0",
    "sonner": "^2.0.7",
    "tailwind-merge": "^3.6.0",
    "tailwindcss": "^4.2.1",
    "zod": "^4.4.3"
  },
  "devDependencies": {
    "@biomejs/biome": "^2.5.6",
    "@hey-api/openapi-ts": "0.97.3",
    "@playwright/test": "1.62.1",
    "@tanstack/router-devtools": "^1.167.0",
    "@tanstack/router-plugin": "^1.168.23",
    "@types/node": "^26.1.2",
    "@types/react": "^19.2.18",
    "@types/react-dom": "^19.2.4",
    "@vitejs/plugin-react-swc": "^4.3.3",
    "dotenv": "^17.4.2",
    "tw-animate-css": "^1.4.0",
    "typescript": "^6.0.3",
    "vite": "^8.2.0"
  }
}
curl: (56) The requested URL returned error: 404
# Full Stack FastAPI Template

[![Test Docker Compose](../../actions/workflows/test-docker-compose.yml/badge.svg)](../../actions/workflows/test-docker-compose.yml)
[![Test Backend](../../actions/workflows/test-backend.yml/badge.svg)](../../actions/workflows/test-backend.yml)

## Technology Stack and Features

- ⚡ [**FastAPI**](https://fastapi.tiangolo.com) for the Python backend API.
  - 🧰 [SQLModel](https://sqlmodel.tiangolo.com) for the Python SQL database interactions (ORM).
  - 🔍 [Pydantic](https://docs.pydantic.dev), used by FastAPI, for the data validation and settings management.
  - 💾 [PostgreSQL](https://www.postgresql.org) as the SQL database.
- 🚀 [React](https://react.dev) for the frontend.
  - 🧩 Built into the backend application and served by FastAPI on the same domain as the API.
  - 💃 Using TypeScript, hooks, [Vite](https://vitejs.dev), and other parts of a modern frontend stack.
  - 🎨 [Tailwind CSS](https://tailwindcss.com) and [shadcn/ui](https://ui.shadcn.com) for the frontend components.
  - 🤖 An automatically generated frontend client.
  - 🧪 [Playwright](https://playwright.dev) for end-to-end testing.
  - 🦇 Dark mode support.
- ☁️ [FastAPI Cloud](https://fastapicloud.com) for deployment.
- 🐋 [Docker Compose](https://www.docker.com) for local services and self-hosted deployment.
  - 📞 [Traefik](https://traefik.io) as a reverse proxy with automatic HTTPS.
- 🔒 Secure password hashing by default.
- 🔑 JWT (JSON Web Token) authentication.
- 📫 Email-based password recovery.
- ✉️ [React Email](https://react.email) for email templates.
- 📬 [Mailpit](https://mailpit.axllent.org) for local email testing during development.
- ✅ Tests with [Pytest](https://pytest.org).
- 🏭 CI (continuous integration) and CD (continuous deployment) based on GitHub Actions.

### Dashboard Login

![Dashboard login screenshot](img/login.png)

### Dashboard - Admin

![Admin dashboard screenshot](img/dashboard.png)

### Dashboard - Items

![Items dashboard screenshot](img/dashboard-items.png)

### Dashboard - Dark Mode

![Dark mode dashboard screenshot](img/dashboard-dark.png)

### React Email Templates

![Email templates screenshot](img/react-email.png)

### Mailpit - Local Email Testing

![Mailpit screenshot](img/mailpit.png)

### Interactive API Documentation

![API docs](img/docs.png)

## How to Use It

Click the **Use this template** button at the top of this page to create a new repository.

## Backend Development

Backend docs: [backend/README.md](./backend/README.md).

## Frontend Development

Frontend docs: [frontend/README.md](./frontend/README.md).

## Deployment

FastAPI Cloud deployment: [deployment.md](./deployment.md).

Self-hosted deployment with Docker Compose: [deployment-docker-compose.md](./deployment-docker-compose.md).

## Development

General development docs: [development.md](./development.md).

This includes the local FastAPI and Vite workflow, Docker Compose services, `.env` configuration, and more.

## Release Notes

Check the file [release-notes.md](./release-notes.md).

## License

The Full Stack FastAPI Template is licensed under the terms of the MIT license.

 succeeded in 1170ms:
from sqlmodel import Session, create_engine, select

from app import crud
from app.core.config import settings
from app.models import User, UserCreate

engine = create_engine(str(settings.DATABASE_URL), pool_pre_ping=True)


# make sure all SQLModel models are imported (app.models) before initializing DB
# otherwise, SQLModel might fail to initialize relationships properly
# for more details: https://github.com/fastapi/full-stack-fastapi-template/issues/28


def init_db(session: Session) -> None:
    # Tables should be created with Alembic migrations
    # But if you don't want to use migrations, create
    # the tables un-commenting the next lines
    # from sqlmodel import SQLModel

    # This works because the models are already imported and registered from app.models
    # SQLModel.metadata.create_all(engine)

    user = session.exec(
        select(User).where(User.email == settings.FIRST_SUPERUSER)
    ).first()
    if not user:
        user_in = UserCreate(
            email=settings.FIRST_SUPERUSER,
            password=settings.FIRST_SUPERUSER_PASSWORD,
            is_superuser=True,
        )
        user = crud.create_user(session=session, user_create=user_in)
import logging

from sqlmodel import Session

from app.core.db import engine, init_db

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


def init() -> None:
    with Session(engine) as session:
        init_db(session)


def main() -> None:
    logger.info("Creating initial data")
    init()
    logger.info("Initial data created")


if __name__ == "__main__":
    main()
import uuid
from unittest.mock import patch

from fastapi.testclient import TestClient
from sqlmodel import Session, select

from app import crud
from app.core.config import settings
from app.core.security import verify_password
from app.models import User, UserCreate
from tests.utils.user import create_random_user
from tests.utils.utils import random_email, random_lower_string


def test_get_users_superuser_me(
    client: TestClient, superuser_token_headers: dict[str, str]
) -> None:
    r = client.get(f"{settings.API_V1_STR}/users/me", headers=superuser_token_headers)
    current_user = r.json()
    assert current_user
    assert current_user["is_active"] is True
    assert current_user["is_superuser"]
    assert current_user["email"] == settings.FIRST_SUPERUSER


def test_get_users_normal_user_me(
    client: TestClient, normal_user_token_headers: dict[str, str]
) -> None:
    r = client.get(f"{settings.API_V1_STR}/users/me", headers=normal_user_token_headers)
    current_user = r.json()
    assert current_user
    assert current_user["is_active"] is True
    assert current_user["is_superuser"] is False
    assert current_user["email"] == settings.EMAIL_TEST_USER


def test_create_user_new_email(
    client: TestClient, superuser_token_headers: dict[str, str], db: Session
) -> None:
    with (
        patch("app.utils.send_email", return_value=None),
        patch("app.core.config.settings.SMTP_HOST", "smtp.example.com"),
        patch("app.core.config.settings.SMTP_USER", "admin@example.com"),
    ):
        username = random_email()
        password = random_lower_string()
        data = {"email": username, "password": password}
        r = client.post(
            f"{settings.API_V1_STR}/users/",
            headers=superuser_token_headers,
            json=data,
        )
        assert 200 <= r.status_code < 300
        created_user = r.json()
        user = crud.get_user_by_email(session=db, email=username)
        assert user
        assert user.email == created_user["email"]


def test_get_existing_user_as_superuser(
    client: TestClient, superuser_token_headers: dict[str, str], db: Session
) -> None:
    username = random_email()
    password = random_lower_string()
    user_in = UserCreate(email=username, password=password)
    user = crud.create_user(session=db, user_create=user_in)
    user_id = user.id
    r = client.get(
        f"{settings.API_V1_STR}/users/{user_id}",
        headers=superuser_token_headers,
    )
    assert 200 <= r.status_code < 300
    api_user = r.json()
    existing_user = crud.get_user_by_email(session=db, email=username)
    assert existing_user
    assert existing_user.email == api_user["email"]


def test_get_non_existing_user_as_superuser(
    client: TestClient, superuser_token_headers: dict[str, str]
) -> None:
    r = client.get(
        f"{settings.API_V1_STR}/users/{uuid.uuid4()}",
        headers=superuser_token_headers,
    )
    assert r.status_code == 404
    assert r.json() == {"detail": "User not found"}


def test_get_existing_user_current_user(client: TestClient, db: Session) -> None:
    username = random_email()
    password = random_lower_string()
    user_in = UserCreate(email=username, password=password)
    user = crud.create_user(session=db, user_create=user_in)
    user_id = user.id

    login_data = {
        "username": username,
        "password": password,
    }
    r = client.post(f"{settings.API_V1_STR}/login/access-token", data=login_data)
    tokens = r.json()
    a_token = tokens["access_token"]
    headers = {"Authorization": f"Bearer {a_token}"}

    r = client.get(
        f"{settings.API_V1_STR}/users/{user_id}",
        headers=headers,
    )
    assert 200 <= r.status_code < 300
    api_user = r.json()
    existing_user = crud.get_user_by_email(session=db, email=username)
    assert existing_user
    assert existing_user.email == api_user["email"]


def test_get_existing_user_permissions_error(
    db: Session,
    client: TestClient,
    normal_user_token_headers: dict[str, str],
) -> None:
    user = create_random_user(db)

    r = client.get(
        f"{settings.API_V1_STR}/users/{user.id}",
        headers=normal_user_token_headers,
    )
    assert r.status_code == 403
    assert r.json() == {"detail": "The user doesn't have enough privileges"}


def test_get_non_existing_user_permissions_error(
    client: TestClient,
    normal_user_token_headers: dict[str, str],
) -> None:
    user_id = uuid.uuid4()

    r = client.get(
        f"{settings.API_V1_STR}/users/{user_id}",
        headers=normal_user_token_headers,
    )
    assert r.status_code == 403
    assert r.json() == {"detail": "The user doesn't have enough privileges"}


def test_create_user_existing_username(
    client: TestClient, superuser_token_headers: dict[str, str], db: Session
) -> None:
    username = random_email()
    # username = email
    password = random_lower_string()
    user_in = UserCreate(email=username, password=password)
    crud.create_user(session=db, user_create=user_in)
    data = {"email": username, "password": password}
    r = client.post(
        f"{settings.API_V1_STR}/users/",
        headers=superuser_token_headers,
        json=data,
    )
    created_user = r.json()
    assert r.status_code == 400
    assert "_id" not in created_user


def test_create_user_by_normal_user(
    client: TestClient, normal_user_token_headers: dict[str, str]
) -> None:
    username = random_email()
    password = random_lower_string()
    data = {"email": username, "password": password}
    r = client.post(
        f"{settings.API_V1_STR}/users/",
        headers=normal_user_token_headers,
        json=data,
    )
    assert r.status_code == 403


def test_retrieve_users(
    client: TestClient, superuser_token_headers: dict[str, str], db: Session
) -> None:
    username = random_email()
    password = random_lower_string()
    user_in = UserCreate(email=username, password=password)
    crud.create_user(session=db, user_create=user_in)

    username2 = random_email()
    password2 = random_lower_string()
    user_in2 = UserCreate(email=username2, password=password2)
    crud.create_user(session=db, user_create=user_in2)

    r = client.get(f"{settings.API_V1_STR}/users/", headers=superuser_token_headers)
    all_users = r.json()

    assert len(all_users["data"]) > 1
    assert "count" in all_users
    for item in all_users["data"]:
        assert "email" in item


def test_update_user_me(
    client: TestClient, normal_user_token_headers: dict[str, str], db: Session
) -> None:
    full_name = "Updated Name"
    email = random_email()
    data = {"full_name": full_name, "email": email}
    r = client.patch(
        f"{settings.API_V1_STR}/users/me",
        headers=normal_user_token_headers,
        json=data,
    )
    assert r.status_code == 200
    updated_user = r.json()
    assert updated_user["email"] == email
    assert updated_user["full_name"] == full_name

    user_query = select(User).where(User.email == email)
    user_db = db.exec(user_query).first()
    assert user_db
    assert user_db.email == email
    assert user_db.full_name == full_name


def test_update_password_me(
    client: TestClient, superuser_token_headers: dict[str, str], db: Session
) -> None:
    new_password = random_lower_string()
    data = {
        "current_password": settings.FIRST_SUPERUSER_PASSWORD,
        "new_password": new_password,
    }
    r = client.patch(
        f"{settings.API_V1_STR}/users/me/password",
        headers=superuser_token_headers,
        json=data,
    )
    assert r.status_code == 200
    updated_user = r.json()
    assert updated_user["message"] == "Password updated successfully"

    user_query = select(User).where(User.email == settings.FIRST_SUPERUSER)
    user_db = db.exec(user_query).first()
    assert user_db
    assert user_db.email == settings.FIRST_SUPERUSER
    verified, _ = verify_password(new_password, user_db.hashed_password)
    assert verified

    # Revert to the old password to keep consistency in test
    old_data = {
        "current_password": new_password,
        "new_password": settings.FIRST_SUPERUSER_PASSWORD,
    }
    r = client.patch(
        f"{settings.API_V1_STR}/users/me/password",
        headers=superuser_token_headers,
        json=old_data,
    )
    db.refresh(user_db)

    assert r.status_code == 200
    verified, _ = verify_password(
        settings.FIRST_SUPERUSER_PASSWORD, user_db.hashed_password
    )
    assert verified


def test_update_password_me_incorrect_password(
    client: TestClient, superuser_token_headers: dict[str, str]
) -> None:
    new_password = random_lower_string()
    data = {"current_password": new_password, "new_password": new_password}
    r = client.patch(
        f"{settings.API_V1_STR}/users/me/password",
        headers=superuser_token_headers,
        json=data,
    )
    assert r.status_code == 400
    updated_user = r.json()
    assert updated_user["detail"] == "Incorrect password"


def test_update_user_me_email_exists(
    client: TestClient, normal_user_token_headers: dict[str, str], db: Session
) -> None:
    username = random_email()
    password = random_lower_string()
    user_in = UserCreate(email=username, password=password)
    user = crud.create_user(session=db, user_create=user_in)

    data = {"email": user.email}
    r = client.patch(
        f"{settings.API_V1_STR}/users/me",
        headers=normal_user_token_headers,
        json=data,
    )
    assert r.status_code == 409
    assert r.json()["detail"] == "User with this email already exists"


def test_update_password_me_same_password_error(
    client: TestClient, superuser_token_headers: dict[str, str]
) -> None:
    data = {
        "current_password": settings.FIRST_SUPERUSER_PASSWORD,
        "new_password": settings.FIRST_SUPERUSER_PASSWORD,
    }
    r = client.patch(
        f"{settings.API_V1_STR}/users/me/password",
        headers=superuser_token_headers,
        json=data,
    )
    assert r.status_code == 400
    updated_user = r.json()
    assert (
        updated_user["detail"] == "New password cannot be the same as the current one"
    )


def test_register_user(client: TestClient, db: Session) -> None:
    username = random_email()
    password = random_lower_string()
    full_name = random_lower_string()
    data = {"email": username, "password": password, "full_name": full_name}
    r = client.post(
        f"{settings.API_V1_STR}/users/signup",
        json=data,
    )
    assert r.status_code == 200
    created_user = r.json()
    assert created_user["email"] == username
    assert created_user["full_name"] == full_name

    user_query = select(User).where(User.email == username)
    user_db = db.exec(user_query).first()
    assert user_db
    assert user_db.email == username
    assert user_db.full_name == full_name
    verified, _ = verify_password(password, user_db.hashed_password)
    assert verified


def test_register_user_already_exists_error(client: TestClient) -> None:
    password = random_lower_string()
    full_name = random_lower_string()
    data = {
        "email": settings.FIRST_SUPERUSER,
        "password": password,
        "full_name": full_name,
    }
    r = client.post(
        f"{settings.API_V1_STR}/users/signup",
        json=data,
    )
    assert r.status_code == 400
    assert r.json()["detail"] == "The user with this email already exists in the system"


def test_update_user(
    client: TestClient, superuser_token_headers: dict[str, str], db: Session
) -> None:
    username = random_email()
    password = random_lower_string()
    user_in = UserCreate(email=username, password=password)
    user = crud.create_user(session=db, user_create=user_in)

    data = {"full_name": "Updated_full_name"}
    r = client.patch(
        f"{settings.API_V1_STR}/users/{user.id}",
        headers=superuser_token_headers,
        json=data,
    )
    assert r.status_code == 200
    updated_user = r.json()

    assert updated_user["full_name"] == "Updated_full_name"

    user_query = select(User).where(User.email == username)
    user_db = db.exec(user_query).first()
    db.refresh(user_db)
    assert user_db
    assert user_db.full_name == "Updated_full_name"


def test_update_user_not_exists(
    client: TestClient, superuser_token_headers: dict[str, str]
) -> None:
    data = {"full_name": "Updated_full_name"}
    r = client.patch(
        f"{settings.API_V1_STR}/users/{uuid.uuid4()}",
        headers=superuser_token_headers,
        json=data,
    )
    assert r.status_code == 404
    assert r.json()["detail"] == "The user with this id does not exist in the system"


def test_update_user_email_exists(
    client: TestClient, superuser_token_headers: dict[str, str], db: Session
) -> None:
    username = random_email()
    password = random_lower_string()
    user_in = UserCreate(email=username, password=password)
    user = crud.create_user(session=db, user_create=user_in)

    username2 = random_email()
    password2 = random_lower_string()
    user_in2 = UserCreate(email=username2, password=password2)
    user2 = crud.create_user(session=db, user_create=user_in2)

    data = {"email": user2.email}
    r = client.patch(
        f"{settings.API_V1_STR}/users/{user.id}",
        headers=superuser_token_headers,
        json=data,
    )
    assert r.status_code == 409
    assert r.json()["detail"] == "User with this email already exists"


def test_delete_user_me(client: TestClient, db: Session) -> None:
    username = random_email()
    password = random_lower_string()
    user_in = UserCreate(email=username, password=password)
    user = crud.create_user(session=db, user_create=user_in)
    user_id = user.id

    login_data = {
        "username": username,
        "password": password,
    }
    r = client.post(f"{settings.API_V1_STR}/login/access-token", data=login_data)
    tokens = r.json()
    a_token = tokens["access_token"]
    headers = {"Authorization": f"Bearer {a_token}"}

    r = client.delete(
        f"{settings.API_V1_STR}/users/me",
        headers=headers,
    )
    assert r.status_code == 200
    deleted_user = r.json()
    assert deleted_user["message"] == "User deleted successfully"
    result = db.exec(select(User).where(User.id == user_id)).first()
    assert result is None

    user_query = select(User).where(User.id == user_id)
    user_db = db.execute(user_query).first()
    assert user_db is None


def test_delete_user_me_as_superuser(
    client: TestClient, superuser_token_headers: dict[str, str]
) -> None:
    r = client.delete(
        f"{settings.API_V1_STR}/users/me",
        headers=superuser_token_headers,
    )
    assert r.status_code == 403
    response = r.json()
    assert response["detail"] == "Super users are not allowed to delete themselves"


def test_delete_user_super_user(
    client: TestClient, superuser_token_headers: dict[str, str], db: Session
) -> None:
    username = random_email()
    password = random_lower_string()
    user_in = UserCreate(email=username, password=password)
    user = crud.create_user(session=db, user_create=user_in)
    user_id = user.id
    r = client.delete(
        f"{settings.API_V1_STR}/users/{user_id}",
        headers=superuser_token_headers,
    )
    assert r.status_code == 200
    deleted_user = r.json()
    assert deleted_user["message"] == "User deleted successfully"
    result = db.exec(select(User).where(User.id == user_id)).first()
    assert result is None


def test_delete_user_not_found(
    client: TestClient, superuser_token_headers: dict[str, str]
) -> None:
    r = client.delete(
        f"{settings.API_V1_STR}/users/{uuid.uuid4()}",
        headers=superuser_token_headers,
    )
    assert r.status_code == 404
    assert r.json()["detail"] == "User not found"


def test_delete_user_current_super_user_error(
    client: TestClient, superuser_token_headers: dict[str, str], db: Session
) -> None:
    super_user = crud.get_user_by_email(session=db, email=settings.FIRST_SUPERUSER)
    assert super_user
    user_id = super_user.id

    r = client.delete(
        f"{settings.API_V1_STR}/users/{user_id}",
        headers=superuser_token_headers,
    )
    assert r.status_code == 403
    assert r.json()["detail"] == "Super users are not allowed to delete themselves"


def test_delete_user_without_privileges(
    client: TestClient, normal_user_token_headers: dict[str, str], db: Session
) -> None:
    username = random_email()
    password = random_lower_string()
    user_in = UserCreate(email=username, password=password)
    user = crud.create_user(session=db, user_create=user_in)

    r = client.delete(
        f"{settings.API_V1_STR}/users/{user.id}",
        headers=normal_user_token_headers,
    )
    assert r.status_code == 403
    assert r.json()["detail"] == "The user doesn't have enough privileges"
from collections.abc import Generator

import pytest
from fastapi.testclient import TestClient
from sqlmodel import Session, delete

from app.core.config import settings
from app.core.db import engine, init_db
from app.main import app
from app.models import Item, User
from tests.utils.user import authentication_token_from_email
from tests.utils.utils import get_superuser_token_headers


@pytest.fixture(scope="session", autouse=True)
def db() -> Generator[Session]:
    with Session(engine) as session:
        init_db(session)
        yield session
        statement = delete(Item)
        session.execute(statement)
        statement = delete(User)
        session.execute(statement)
        session.commit()


@pytest.fixture(scope="module")
def client() -> Generator[TestClient]:
    with TestClient(app) as c:
        yield c


@pytest.fixture(scope="module")
def superuser_token_headers(client: TestClient) -> dict[str, str]:
    return get_superuser_token_headers(client)


@pytest.fixture(scope="module")
def normal_user_token_headers(client: TestClient, db: Session) -> dict[str, str]:
    return authentication_token_from_email(
        client=client, email=settings.EMAIL_TEST_USER, db=db
    )

 succeeded in 1405ms:
import uuid
from datetime import UTC, datetime

from pydantic import EmailStr
from sqlalchemy import DateTime
from sqlmodel import Field, Relationship, SQLModel


def get_datetime_utc() -> datetime:
    return datetime.now(UTC)


# Shared properties
class UserBase(SQLModel):
    email: EmailStr = Field(unique=True, index=True, max_length=255)
    is_active: bool = True
    is_superuser: bool = False
    full_name: str | None = Field(default=None, max_length=255)


# Properties to receive via API on creation
class UserCreate(UserBase):
    password: str = Field(min_length=8, max_length=128)


class UserRegister(SQLModel):
    email: EmailStr = Field(max_length=255)
    password: str = Field(min_length=8, max_length=128)
    full_name: str | None = Field(default=None, max_length=255)


# Properties to receive via API on update, all are optional
class UserUpdate(SQLModel):
    email: EmailStr | None = Field(default=None, max_length=255)
    is_active: bool | None = None
    is_superuser: bool | None = None
    full_name: str | None = Field(default=None, max_length=255)
    password: str | None = Field(default=None, min_length=8, max_length=128)


class UserUpdateMe(SQLModel):
    full_name: str | None = Field(default=None, max_length=255)
    email: EmailStr | None = Field(default=None, max_length=255)


class UpdatePassword(SQLModel):
    current_password: str = Field(min_length=8, max_length=128)
    new_password: str = Field(min_length=8, max_length=128)


# Database model, database table inferred from class name
class User(UserBase, table=True):
    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    hashed_password: str
    created_at: datetime | None = Field(
        default_factory=get_datetime_utc,
        sa_type=DateTime(timezone=True),  # type: ignore
    )
    items: list[Item] = Relationship(back_populates="owner", cascade_delete=True)


# Properties to return via API, id is always required
class UserPublic(UserBase):
    id: uuid.UUID
    created_at: datetime | None = None


class UsersPublic(SQLModel):
    data: list[UserPublic]
    count: int


# Shared properties
class ItemBase(SQLModel):
    title: str = Field(min_length=1, max_length=255)
    description: str | None = Field(default=None, max_length=255)


# Properties to receive on item creation
class ItemCreate(ItemBase):
    pass


# Properties to receive on item update
class ItemUpdate(SQLModel):
    title: str | None = Field(default=None, min_length=1, max_length=255)
    description: str | None = Field(default=None, max_length=255)


# Database model, database table inferred from class name
class Item(ItemBase, table=True):
    id: uuid.UUID = Field(default_factory=uuid.uuid4, primary_key=True)
    created_at: datetime | None = Field(
        default_factory=get_datetime_utc,
        sa_type=DateTime(timezone=True),  # type: ignore
    )
    owner_id: uuid.UUID = Field(
        foreign_key="user.id", nullable=False, ondelete="CASCADE"
    )
    owner: User | None = Relationship(back_populates="items")


# Properties to return via API, id is always required
class ItemPublic(ItemBase):
    id: uuid.UUID
    owner_id: uuid.UUID
    created_at: datetime | None = None


class ItemsPublic(SQLModel):
    data: list[ItemPublic]
    count: int


# Generic message
class Message(SQLModel):
    message: str


# JSON payload containing access token
class Token(SQLModel):
    access_token: str
    token_type: str = "bearer"


# Contents of JWT token
class TokenPayload(SQLModel):
    sub: str | None = None


class NewPassword(SQLModel):
    token: str
    new_password: str = Field(min_length=8, max_length=128)
from collections.abc import Generator
from typing import Annotated

import jwt
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jwt.exceptions import InvalidTokenError
from pydantic import ValidationError
from sqlmodel import Session

from app.core import security
from app.core.config import settings
from app.core.db import engine
from app.models import TokenPayload, User

reusable_oauth2 = OAuth2PasswordBearer(
    tokenUrl=f"{settings.API_V1_STR}/login/access-token"
)


def get_db() -> Generator[Session]:
    with Session(engine) as session:
        yield session


SessionDep = Annotated[Session, Depends(get_db)]
TokenDep = Annotated[str, Depends(reusable_oauth2)]


def get_current_user(session: SessionDep, token: TokenDep) -> User:
    try:
        payload = jwt.decode(
            token, settings.SECRET_KEY, algorithms=[security.ALGORITHM]
        )
        token_data = TokenPayload(**payload)
    except InvalidTokenError, ValidationError:
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail="Could not validate credentials",
        )
    user = session.get(User, token_data.sub)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if not user.is_active:
        raise HTTPException(status_code=400, detail="Inactive user")
    return user


CurrentUser = Annotated[User, Depends(get_current_user)]


def get_current_active_superuser(current_user: CurrentUser) -> User:
    if not current_user.is_superuser:
        raise HTTPException(
            status_code=403, detail="The user doesn't have enough privileges"
        )
    return current_user
import uuid
from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from sqlmodel import col, delete, func, select

from app import crud
from app.api.deps import (
    CurrentUser,
    SessionDep,
    get_current_active_superuser,
)
from app.core.config import settings
from app.core.security import get_password_hash, verify_password
from app.models import (
    Item,
    Message,
    UpdatePassword,
    User,
    UserCreate,
    UserPublic,
    UserRegister,
    UsersPublic,
    UserUpdate,
    UserUpdateMe,
)
from app.utils import generate_new_account_email, send_email

router = APIRouter(prefix="/users", tags=["users"])


@router.get(
    "/",
    dependencies=[Depends(get_current_active_superuser)],
    response_model=UsersPublic,
)
def read_users(session: SessionDep, skip: int = 0, limit: int = 100) -> Any:
    """
    Retrieve users.
    """

    count_statement = select(func.count()).select_from(User)
    count = session.exec(count_statement).one()

    statement = (
        select(User).order_by(col(User.created_at).desc()).offset(skip).limit(limit)
    )
    users = session.exec(statement).all()

    users_public = [UserPublic.model_validate(user) for user in users]
    return UsersPublic(data=users_public, count=count)


@router.post(
    "/", dependencies=[Depends(get_current_active_superuser)], response_model=UserPublic
)
def create_user(*, session: SessionDep, user_in: UserCreate) -> Any:
    """
    Create new user.
    """
    user = crud.get_user_by_email(session=session, email=user_in.email)
    if user:
        raise HTTPException(
            status_code=400,
            detail="The user with this email already exists in the system.",
        )

    user = crud.create_user(session=session, user_create=user_in)
    if settings.emails_enabled and user_in.email:
        email_data = generate_new_account_email(
            email_to=user_in.email, username=user_in.email, password=user_in.password
        )
        send_email(
            email_to=user_in.email,
            subject=email_data.subject,
            html_content=email_data.html_content,
        )
    return user


@router.patch("/me", response_model=UserPublic)
def update_user_me(
    *, session: SessionDep, user_in: UserUpdateMe, current_user: CurrentUser
) -> Any:
    """
    Update own user.
    """

    if user_in.email:
        existing_user = crud.get_user_by_email(session=session, email=user_in.email)
        if existing_user and existing_user.id != current_user.id:
            raise HTTPException(
                status_code=409, detail="User with this email already exists"
            )
    user_data = user_in.model_dump(exclude_unset=True)
    current_user.sqlmodel_update(user_data)
    session.add(current_user)
    session.commit()
    session.refresh(current_user)
    return current_user


@router.patch("/me/password", response_model=Message)
def update_password_me(
    *, session: SessionDep, body: UpdatePassword, current_user: CurrentUser
) -> Any:
    """
    Update own password.
    """
    verified, _ = verify_password(body.current_password, current_user.hashed_password)
    if not verified:
        raise HTTPException(status_code=400, detail="Incorrect password")
    if body.current_password == body.new_password:
        raise HTTPException(
            status_code=400, detail="New password cannot be the same as the current one"
        )
    hashed_password = get_password_hash(body.new_password)
    current_user.hashed_password = hashed_password
    session.add(current_user)
    session.commit()
    return Message(message="Password updated successfully")


@router.get("/me", response_model=UserPublic)
def read_user_me(current_user: CurrentUser) -> Any:
    """
    Get current user.
    """
    return current_user


@router.delete("/me", response_model=Message)
def delete_user_me(session: SessionDep, current_user: CurrentUser) -> Any:
    """
    Delete own user.
    """
    if current_user.is_superuser:
        raise HTTPException(
            status_code=403, detail="Super users are not allowed to delete themselves"
        )
    session.delete(current_user)
    session.commit()
    return Message(message="User deleted successfully")


@router.post("/signup", response_model=UserPublic)
def register_user(session: SessionDep, user_in: UserRegister) -> Any:
    """
    Create new user without the need to be logged in.
    """
    user = crud.get_user_by_email(session=session, email=user_in.email)
    if user:
        raise HTTPException(
            status_code=400,
            detail="The user with this email already exists in the system",
        )
    user_create = UserCreate.model_validate(user_in)
    user = crud.create_user(session=session, user_create=user_create)
    return user


@router.get("/{user_id}", response_model=UserPublic)
def read_user_by_id(
    user_id: uuid.UUID, session: SessionDep, current_user: CurrentUser
) -> Any:
    """
    Get a specific user by id.
    """
    user = session.get(User, user_id)
    if user == current_user:
        return user
    if not current_user.is_superuser:
        raise HTTPException(
            status_code=403,
            detail="The user doesn't have enough privileges",
        )
    if user is None:
        raise HTTPException(status_code=404, detail="User not found")
    return user


@router.patch(
    "/{user_id}",
    dependencies=[Depends(get_current_active_superuser)],
    response_model=UserPublic,
)
def update_user(
    *,
    session: SessionDep,
    user_id: uuid.UUID,
    user_in: UserUpdate,
) -> Any:
    """
    Update a user.
    """

    db_user = session.get(User, user_id)
    if not db_user:
        raise HTTPException(
            status_code=404,
            detail="The user with this id does not exist in the system",
        )
    if user_in.email:
        existing_user = crud.get_user_by_email(session=session, email=user_in.email)
        if existing_user and existing_user.id != user_id:
            raise HTTPException(
                status_code=409, detail="User with this email already exists"
            )

    db_user = crud.update_user(session=session, db_user=db_user, user_in=user_in)
    return db_user


@router.delete("/{user_id}", dependencies=[Depends(get_current_active_superuser)])
def delete_user(
    session: SessionDep, current_user: CurrentUser, user_id: uuid.UUID
) -> Message:
    """
    Delete a user.
    """
    user = session.get(User, user_id)
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    if user == current_user:
        raise HTTPException(
            status_code=403, detail="Super users are not allowed to delete themselves"
        )
    statement = delete(Item).where(col(Item.owner_id) == user_id)
    session.exec(statement)
    session.delete(user)
    session.commit()
    return Message(message="User deleted successfully")
from fastapi import APIRouter

from app.api.routes import items, login, private, users, utils
from app.core.config import settings

api_router = APIRouter()
api_router.include_router(login.router)
api_router.include_router(users.router)
api_router.include_router(utils.router)
api_router.include_router(items.router)


if settings.FASTAPI_ENV == "development":
    api_router.include_router(private.router)

 succeeded in 1439ms:
import { useMutation, useQuery, useQueryClient } from "@tanstack/react-query"
import { useNavigate } from "@tanstack/react-router"

import {
  type Body_login_login_access_token as AccessToken,
  LoginService,
  type UserPublic,
  type UserRegister,
  UsersService,
} from "@/client"
import { handleError } from "@/utils"
import useCustomToast from "./useCustomToast"

const isLoggedIn = () => {
  return localStorage.getItem("access_token") !== null
}

const useAuth = () => {
  const navigate = useNavigate()
  const queryClient = useQueryClient()
  const { showErrorToast } = useCustomToast()

  const { data: user } = useQuery<UserPublic | null, Error>({
    queryKey: ["currentUser"],
    queryFn: async () => (await UsersService.readUserMe()).data,
    enabled: isLoggedIn(),
  })

  const signUpMutation = useMutation({
    mutationFn: (data: UserRegister) =>
      UsersService.registerUser({ body: data }),
    onSuccess: () => {
      navigate({ to: "/login" })
    },
    onError: handleError.bind(showErrorToast),
    onSettled: () => {
      queryClient.invalidateQueries({ queryKey: ["users"] })
    },
  })

  const login = async (data: AccessToken) => {
    const response = await LoginService.loginAccessToken({
      body: data,
    })
    localStorage.setItem("access_token", response.data.access_token)
  }

  const loginMutation = useMutation({
    mutationFn: login,
    onSuccess: () => {
      navigate({ to: "/" })
    },
    onError: handleError.bind(showErrorToast),
  })

  const logout = () => {
    localStorage.removeItem("access_token")
    navigate({ to: "/login" })
  }

  return {
    signUpMutation,
    loginMutation,
    logout,
    user,
  }
}

export { isLoggedIn }
export default useAuth
import { createFileRoute, Outlet, redirect } from "@tanstack/react-router"

import { Footer } from "@/components/Common/Footer"
import AppSidebar from "@/components/Sidebar/AppSidebar"
import {
  SidebarInset,
  SidebarProvider,
  SidebarTrigger,
} from "@/components/ui/sidebar"
import { isLoggedIn } from "@/hooks/useAuth"

export const Route = createFileRoute("/_layout")({
  component: Layout,
  beforeLoad: async () => {
    if (!isLoggedIn()) {
      throw redirect({
        to: "/login",
      })
    }
  },
})

function Layout() {
  return (
    <SidebarProvider>
      <AppSidebar />
      <SidebarInset>
        <header className="sticky top-0 z-10 flex h-16 shrink-0 items-center gap-2 border-b bg-background px-4">
          <SidebarTrigger className="-ml-1 text-muted-foreground" />
        </header>
        <main className="flex-1 p-6 md:p-8">
          <div className="mx-auto max-w-7xl">
            <Outlet />
          </div>
        </main>
        <Footer />
      </SidebarInset>
    </SidebarProvider>
  )
}
import { useSuspenseQuery } from "@tanstack/react-query"
import { createFileRoute, redirect } from "@tanstack/react-router"
import { Suspense } from "react"

import { type UserPublic, UsersService } from "@/client"
import AddUser from "@/components/Admin/AddUser"
import { columns, type UserTableData } from "@/components/Admin/columns"
import { DataTable } from "@/components/Common/DataTable"
import PendingUsers from "@/components/Pending/PendingUsers"
import useAuth from "@/hooks/useAuth"

function getUsersQueryOptions() {
  return {
    queryFn: async () =>
      (await UsersService.readUsers({ query: { skip: 0, limit: 100 } })).data,
    queryKey: ["users"],
  }
}

export const Route = createFileRoute("/_layout/admin")({
  component: Admin,
  beforeLoad: async () => {
    const { data: user } = await UsersService.readUserMe()
    if (!user.is_superuser) {
      throw redirect({
        to: "/",
      })
    }
  },
  head: () => ({
    meta: [
      {
        title: "Admin - FastAPI Template",
      },
    ],
  }),
})

function UsersTableContent() {
  const { user: currentUser } = useAuth()
  const { data: users } = useSuspenseQuery(getUsersQueryOptions())

  const tableData: UserTableData[] = users.data.map((user: UserPublic) => ({
    ...user,
    isCurrentUser: currentUser?.id === user.id,
  }))

  return <DataTable columns={columns} data={tableData} />
}

function UsersTable() {
  return (
    <Suspense fallback={<PendingUsers />}>
      <UsersTableContent />
    </Suspense>
  )
}

function Admin() {
  return (
    <div className="flex flex-col gap-6">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-2xl font-bold tracking-tight">Users</h1>
          <p className="text-muted-foreground">
            Manage user accounts and permissions
          </p>
        </div>
        <AddUser />
      </div>
      <UsersTable />
    </div>
  )
}
import { Briefcase, Home, Users } from "lucide-react"

import { SidebarAppearance } from "@/components/Common/Appearance"
import { Logo } from "@/components/Common/Logo"
import {
  Sidebar,
  SidebarContent,
  SidebarFooter,
  SidebarHeader,
} from "@/components/ui/sidebar"
import useAuth from "@/hooks/useAuth"
import { type Item, Main } from "./Main"
import { User } from "./User"

const baseItems: Item[] = [
  { icon: Home, title: "Dashboard", path: "/" },
  { icon: Briefcase, title: "Items", path: "/items" },
]

export function AppSidebar() {
  const { user: currentUser } = useAuth()

  const items = currentUser?.is_superuser
    ? [...baseItems, { icon: Users, title: "Admin", path: "/admin" }]
    : baseItems

  return (
    <Sidebar collapsible="icon">
      <SidebarHeader className="px-4 py-6 group-data-[collapsible=icon]:px-0 group-data-[collapsible=icon]:items-center">
        <Logo variant="responsive" />
      </SidebarHeader>
      <SidebarContent>
        <Main items={items} />
      </SidebarContent>
      <SidebarFooter>
        <SidebarAppearance />
        <User user={currentUser} />
      </SidebarFooter>
    </Sidebar>
  )
}

export default AppSidebar

codex
Картина ясна: upstream уже имеет JWT-аутентификацию, `is_superuser`, защищённый `/users`, профиль `/users/me`, React Router и сгенерированный API-клиент. Поэтому RBAC лучше встроить в эти швы, но по локальному `CLAUDE.md` авторизацию нужно вынести в чистое ядро, а не размазывать проверки ролей по роутам. Осталось зафиксировать минимальный набор файлов, тестов и главный миграционный риск.
exec
/bin/zsh -lc "git status --short --branch && curl -sS -o /dev/null -w '%{http_code}\\n' https://api.github.com/repos/jeksman/fullstack-dev-test-task && curl -fsSL 'https://api.github.com/repos/fastapi/full-stack-fastapi-template/commits/master' | jq -r '.sha, .commit.committer.date'" in /Users/johndoe/Desktop/PERSONAL/test_tasks/Fullstack-Dev-Test-Task
 succeeded in 490ms:
404
486f054cc8d1aead59ec96cc0a16933d06c10e0d
2026-08-28T11:53:12Z

codex
**TL;DR**: добавить централизованную модель `Role → Permission`, проверять права в backend use cases, отдавать вычисленные permissions фронтенду и закрыть миграцией переход с `is_superuser`. Сейчас реализацию начинать рано: шаблон отсутствует в рабочей ветке, `origin` указывает не на целевой репозиторий, а `jeksman/fullstack-dev-test-task` возвращает 404.

### Что менять

1. **Основа проекта**

   Импортировать актуальный [`full-stack-fastapi-template`](https://github.com/fastapi/full-stack-fastapi-template/tree/master), сохранив текущую историю задания. Перед будущим push отдельно настроить целевой remote.

2. **Доменная модель**

   Создать:

   - `backend/app/core/domain/authorization.py`: `Role`, `Permission`, единый `ROLE_PERMISSIONS`;
   - доменную `User`-сущность и исключения `AccessDenied`, `UserNotFound`;
   - `AuthorizationPolicy.require(role, permission)`.

   Матрица:

   | Действие | admin | manager | member |
   |---|---:|---:|---:|
   | Список пользователей | ✓ | ✓ | — |
   | Создание пользователя | ✓ | — | — |
   | Метрики | ✓ | ✓ | — |
   | Свой профиль | ✓ | ✓ | ✓ |
   | Изменение любого профиля | ✓ | — | — |

3. **База данных**

   В `backend/app/models.py` добавить обязательную колонку `role`. Alembic-миграция должна:

   - создать колонку;
   - назначить `admin` существующим `is_superuser=true`;
   - остальным назначить `member`;
   - только после backfill сделать поле `NOT NULL`.

   `is_superuser` оставить для совместимости, но больше не использовать при принятии решений.

4. **Backend**

   Добавить порты репозитория, SQLModel-адаптер и use cases:

   - `ListUsersUseCase`;
   - `CreateUserUseCase`;
   - `UpdateOwnProfileUseCase`;
   - `UpdateAnyProfileUseCase`;
   - `ViewMetricsUseCase`.

   Сборка зависимостей — в `app/api/deps.py`. Роуты лишь преобразуют HTTP DTO и доменные ошибки. Проверка выполняется **до обращения к репозиторию**, отказ логируется и возвращает `403`.

   Добавить:

   - `GET /users/me/permissions`;
   - `GET /metrics`;
   - запрет передавать `role` через `/users/me`;
   - фиксированный `member` для публичной регистрации.

5. **Frontend**

   После изменения OpenAPI пересоздать клиент. Добавить:

   - `usePermissions`;
   - компонент/функцию `Can`;
   - permission-based sidebar;
   - guard для `/users` и `/metrics`;
   - отдельную дружелюбную страницу `Access Denied`;
   - на странице пользователей показывать список manager’у, но кнопку создания — только admin’у.

   Это заменит текущие проверки `user.is_superuser` в [`admin.tsx`](https://github.com/fastapi/full-stack-fastapi-template/blob/master/frontend/src/routes/_layout/admin.tsx) и sidebar.

6. **Тесты и документация**

   Минимальный полезный набор:

   - параметризованный unit-тест всей матрицы;
   - manager может читать список, member получает `403`;
   - admin создаёт пользователя, manager получает `403`;
   - admin/manager видят metrics, member — нет;
   - каждый пользователь обновляет себя, но не может изменить роль;
   - обязательный AST-тест архитектурных границ из `CLAUDE.md`.

   README: матрица, запуск, seed admin/member/manager, миграции, тесты и 2–4 абзаца об архитектуре. Один ADR о централизованной policy-модели будет достаточным.

### Главный риск

**Миграция с `is_superuser` на `role`.** Ошибка backfill или одновременное использование двух источников истины способна либо лишить администратора доступа, либо дать лишние права. Поэтому миграция должна быть протестирована отдельно, а после неё все authorization-решения обязаны использовать только `role`.

Файлы не изменялись; рабочее дерево осталось в исходном состоянии.
tokens used
48 626
**TL;DR**: добавить централизованную модель `Role → Permission`, проверять права в backend use cases, отдавать вычисленные permissions фронтенду и закрыть миграцией переход с `is_superuser`. Сейчас реализацию начинать рано: шаблон отсутствует в рабочей ветке, `origin` указывает не на целевой репозиторий, а `jeksman/fullstack-dev-test-task` возвращает 404.

### Что менять

1. **Основа проекта**

   Импортировать актуальный [`full-stack-fastapi-template`](https://github.com/fastapi/full-stack-fastapi-template/tree/master), сохранив текущую историю задания. Перед будущим push отдельно настроить целевой remote.

2. **Доменная модель**

   Создать:

   - `backend/app/core/domain/authorization.py`: `Role`, `Permission`, единый `ROLE_PERMISSIONS`;
   - доменную `User`-сущность и исключения `AccessDenied`, `UserNotFound`;
   - `AuthorizationPolicy.require(role, permission)`.

   Матрица:

   | Действие | admin | manager | member |
   |---|---:|---:|---:|
   | Список пользователей | ✓ | ✓ | — |
   | Создание пользователя | ✓ | — | — |
   | Метрики | ✓ | ✓ | — |
   | Свой профиль | ✓ | ✓ | ✓ |
   | Изменение любого профиля | ✓ | — | — |

3. **База данных**

   В `backend/app/models.py` добавить обязательную колонку `role`. Alembic-миграция должна:

   - создать колонку;
   - назначить `admin` существующим `is_superuser=true`;
   - остальным назначить `member`;
   - только после backfill сделать поле `NOT NULL`.

   `is_superuser` оставить для совместимости, но больше не использовать при принятии решений.

4. **Backend**

   Добавить порты репозитория, SQLModel-адаптер и use cases:

   - `ListUsersUseCase`;
   - `CreateUserUseCase`;
   - `UpdateOwnProfileUseCase`;
   - `UpdateAnyProfileUseCase`;
   - `ViewMetricsUseCase`.

   Сборка зависимостей — в `app/api/deps.py`. Роуты лишь преобразуют HTTP DTO и доменные ошибки. Проверка выполняется **до обращения к репозиторию**, отказ логируется и возвращает `403`.

   Добавить:

   - `GET /users/me/permissions`;
   - `GET /metrics`;
   - запрет передавать `role` через `/users/me`;
   - фиксированный `member` для публичной регистрации.

5. **Frontend**

   После изменения OpenAPI пересоздать клиент. Добавить:

   - `usePermissions`;
   - компонент/функцию `Can`;
   - permission-based sidebar;
   - guard для `/users` и `/metrics`;
   - отдельную дружелюбную страницу `Access Denied`;
   - на странице пользователей показывать список manager’у, но кнопку создания — только admin’у.

   Это заменит текущие проверки `user.is_superuser` в [`admin.tsx`](https://github.com/fastapi/full-stack-fastapi-template/blob/master/frontend/src/routes/_layout/admin.tsx) и sidebar.

6. **Тесты и документация**

   Минимальный полезный набор:

   - параметризованный unit-тест всей матрицы;
   - manager может читать список, member получает `403`;
   - admin создаёт пользователя, manager получает `403`;
   - admin/manager видят metrics, member — нет;
   - каждый пользователь обновляет себя, но не может изменить роль;
   - обязательный AST-тест архитектурных границ из `CLAUDE.md`.

   README: матрица, запуск, seed admin/member/manager, миграции, тесты и 2–4 абзаца об архитектуре. Один ADR о централизованной policy-модели будет достаточным.

### Главный риск

**Миграция с `is_superuser` на `role`.** Ошибка backfill или одновременное использование двух источников истины способна либо лишить администратора доступа, либо дать лишние права. Поэтому миграция должна быть протестирована отдельно, а после неё все authorization-решения обязаны использовать только `role`.

Файлы не изменялись; рабочее дерево осталось в исходном состоянии.
