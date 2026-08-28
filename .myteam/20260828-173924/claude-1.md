Шаблон прочитал (склонировал в `/tmp/fst`, репо не трогал). Разбор ниже.

## Что есть сейчас

Права = один булев `User.is_superuser`. Проверка — `get_current_active_superuser` в `backend/app/api/deps.py:50`, навешана как `dependencies=[Depends(...)]` на роуты в `routes/users.py`. Фронт: `AppSidebar.tsx:23` прячет пункт по `is_superuser`, `routes/_layout/admin.tsx:22` в `beforeLoad` молча редиректит на `/`. То есть каркас под RBAC уже правильной формы — нужно заменить булев на роль и один флаг на таблицу прав.

## Что менять

**L1 — `app/core/domain/permissions.py`** (только stdlib): `Role(StrEnum)`, `Permission(StrEnum)`, `ROLE_PERMISSIONS: dict[Role, frozenset[Permission]]`. Единственный источник истины; новая роль = одна строка.

**L2 — `app/core/use_cases/authorization.py`**: `AuthorizationPolicy.require(role, permission)` — чистая функция, кидает доменное `AccessDenied`. Тестируется без БД и HTTP.

**L3 — `deps.py`**: фабрика `require(Permission.USER_LIST) -> Depends`, которая достаёт `CurrentUser`, зовёт политику, логирует отказ (кто/право/ресурс) и переводит `AccessDenied` в 403. Все защищённые роуты переходят на один паттерн: `dependencies=[Depends(require(Permission.X))]` вместо `get_current_active_superuser`.

**Эндпоинты**: `GET /users/me/permissions` (фронт узнаёт возможности от бэка, не из захардкоженного TS) + `GET /metrics` — стаб с двумя `count(*)` под `Permission.METRICS_VIEW`.

**L4 — схема**: колонка `role` в `User` + миграция Alembic с backfill `role='admin' WHERE is_superuser`. `UserUpdateMe` роль не содержит → эскалация через `PATCH /users/me` закрыта по конструкции, отдельным тестом фиксируется.

**Фронт**: хук `usePermissions()` поверх `/users/me/permissions` → `can(perm)`; сайдбар фильтруется через `can`, `admin.tsx` и новый `metrics.tsx` в `beforeLoad` вместо тихого редиректа рендерят `<Forbidden />`. После бэкенда — `bun run generate-client`.

**Тесты** (5): таблица политики параметризованная без БД; `GET /users/` — 403 member / 200 manager; `POST /users/` — 403 manager / 200 admin; `PATCH /users/me` с `role: admin` роль не меняет; `test_architecture.py` (запрет фреймворковых импортов в ядре — требование CLAUDE.md).

**Доки**: README (матрица, setup, seed, тесты), 2 ADR (почему dependency-фабрика, а не middleware/декоратор; почему `role` — SSOT), NOTES.md со срезами.

## Главный риск

Два источника истины прав: старый `is_superuser` остаётся в БД, схемах (`UserCreate`, `UserUpdate`), в 11 местах существующих тестов и в четырёх местах фронта (`columns.tsx`, `AddUser`, `EditUser`). Пока оба поля живы, они разъезжаются: админ снимает `role`, но `is_superuser` остаётся `true` — и любой не переведённый на `require()` кусок (например `read_user_by_id`, где проверка написана руками внутри тела) продолжает пускать. Митигация: `is_superuser` делается производным — выставляется из `role` в одном месте (`crud.create_user` / `crud.update_user`), и `grep is_superuser` по `app/` после правки должен давать только эти две строки плюс модель.

## Вопрос по объёму

`CLAUDE.md` требует полный Clean Architecture для users-домена (порты, репозитории, use cases, мапперы), задание требует «keep scope tight, favor clarity over cleverness» за час. Предлагаю CA только для authz-ядра (домен + политика + тест архитектуры), а `crud.py` и роуты оставить как в шаблоне — без портов и мапперов вокруг CRUD, который никто не просил переписывать. Скажи, если нужен полный вариант из гайдлайнов — сделаю его.
