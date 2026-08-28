Шаблон изучил (склонировал в `/tmp/fstpl`, репозиторий не трогал). В нём сейчас: `is_superuser` как единственный флаг прав, `get_current_active_superuser` в `deps.py`, на фронте `!user.is_superuser` в `beforeLoad` у `routes/_layout/admin.tsx`.

## Что менять

**1. Одна таблица прав — `backend/app/core/rbac.py`**
```python
class Role(StrEnum): ADMIN, MANAGER, MEMBER
class Permission(StrEnum): USER_LIST, USER_CREATE, USER_UPDATE_ANY, METRICS_VIEW, PROFILE_UPDATE_OWN
ROLE_PERMISSIONS: dict[Role, frozenset[Permission]]
def has(role, perm) -> bool
```
Новая роль = одна строка в словаре. Чистая функция — тестируется без БД и без HTTP.

**2. `models.py`: колонка `role` в `UserBase`**, дефолт `MEMBER`. Alembic-миграция + backfill `role='admin' WHERE is_superuser`. `is_superuser` остаётся в БД ради миграций, но перестаёт быть источником истины — держим его производным от `role` в одном месте (`crud.create_user` / `crud.update_user`), а не в каждом обработчике.

**3. `deps.py`: фабрика зависимостей вместо флага**
```python
def require(*perms: Permission) -> Callable[[CurrentUser], User]
```
403 + лог `(user_id, permission, path)` при отказе. Ею заменяются все `Depends(get_current_active_superuser)` в `users.py` и `private.py`. Паттерн один на весь backend.

**4. Поверхность**: `GET /users/` → `USER_LIST`, `POST /users/` → `USER_CREATE`, `PATCH /users/{id}` → `USER_UPDATE_ANY`, новый `GET /metrics/summary` (заглушка с 3 числами) → `METRICS_VIEW`, `PATCH /users/me` — любой аутентифицированный.

**5. Анти-эскалация**: `UserUpdateMe` не содержит `role` (и не должен) — тест на это обязателен; `/users/signup` всегда выдаёт `MEMBER`; выдать роль может только владелец `USER_UPDATE_ANY`, т.е. admin.

**6. `GET /users/me/permissions` → `{"permissions": [...]}`** — фронт не хардкодит роли в TS. Хук `usePermissions()`, фильтрация пунктов в `Sidebar/Main.tsx` по правам, в `beforeLoad` у `admin.tsx` и нового `metrics.tsx` — проверка права и рендер `<Forbidden/>` вместо `redirect({to: "/"})` (сейчас шаблон молча редиректит — это ровно тот «fail silently», который задание запрещает). Клиент придётся перегенерить: `bun run generate-client`.

**7. Тесты** (`backend/tests/test_rbac.py`, 5 шт.): матрица прав как чистая функция; manager 200 на `GET /users/`; manager 403 на `POST /users/`; member 403 на `/metrics/summary`; member не может поднять себе роль через `PATCH /users/me`. Фикстуры токенов трёх ролей — в `conftest.py`.

**8. README**: матрица, 3 абзаца про подход, seed трёх юзеров (`initial_data.py`), команды запуска и `bash scripts/test.sh`.

## Главный риск

**Две параллельные истины о правах.** `is_superuser` остаётся в БД, в `UserPublic`, в существующих тестах шаблона и в JS-клиенте; `role` становится новой. Любое место, где они разъезжаются (админ создан со `is_superuser=True`, но `role='member'` — или наоборот), — это либо дыра, либо ложный 403. Митигация: синхронизация ровно в одном месте (`crud`), а решение о доступе читает **только** `role`; `is_superuser` нигде не участвует в авторизации после рефакторинга.

Второй по величине — рассинхрон фронта: если забыть `generate-client`, TS соберётся на старых типах и `permissions` не появится.

## Конфликт, который надо решить до реализации

`CLAUDE.md` требует полный Clean Architecture для users-домена: порты, репозитории, юзкейсы, мапперы, `test_architecture.py` с AST-обходом. Задание требует «keep scope tight, favor clarity over cleverness» в час. Это несовместимо: CA-обвязка вокруг `ListUsersUseCase` — это ~10 новых файлов ради того, что в шаблоне уже работает тремя строками.

Рекомендую: CA применить **только к authz-ядру** — `core/domain/rbac.py` (L1, чистый stdlib) + `test_architecture.py`, который стережёт именно его; репозитории/юзкейсы для users не вводить. Это даёт проверяемую границу и «5 минут на понимание», без десяти файлов-переходников. Если нужен полный вариант из `CLAUDE.md` — скажи, сделаю его, но это уже не часовой объём и ревьюер увидит over-engineering.
