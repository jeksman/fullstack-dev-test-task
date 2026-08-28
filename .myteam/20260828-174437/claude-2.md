Проверил факты в шаблоне (`/tmp/fst`, `486f054`) и локальный тулчейн.

## Мои ошибки

1. **`private.py`** — я написал «заменить там `Depends(get_current_active_superuser)`». Его там нет: роут вообще без авторизации, подключается только при `FASTAPI_ENV == "development"`. Трогать нечего.
2. **Пропустил два superuser-гейта**: `login.py:102` (recover-password-html-content) и `utils.py:13` (test-email). Codex их нашёл — забираю.
3. **Пропустил `is_superuser` внутри тел обработчиков**: `items.py:21,56,89,109`, `users.py:137` (`delete_user_me`), `users.py:172` (`read_user_by_id`). Это 6 мест, где решение о доступе принимается флагом, а не ролью. Мой план их не покрывал — а это ровно тот «второй источник истины», который я сам назвал главным риском.

## Где неправ Codex

- **Фронт он недооценил.** Он говорит только про видимость ссылок. Реально на `is_superuser` завязаны формы: `AddUser.tsx:45,69,189` (чекбокс «superuser»), `EditUser.tsx:44,71,191`, `columns.tsx:42-46` (бейдж «Superuser/User»). Если `role` — новый источник истины, admin через UI не сможет выдать роль. Эти три файла — обязательная часть работы, не «полировка».
- **`settings.tsx:28`** — мёртвая ветка: `is_superuser ? tabsConfig.slice(0,3) : tabsConfig`, обе дают одни и те же 3 таба. Ревьюер по матрице пойдёт смотреть «settings» именно сюда.
- **Он не назвал последствие для существующих тестов.** `UserPublic` отдаёт `is_superuser`, `test_users.py` и `conftest.py` на нём построены. Значит поле обязано остаться и синхронно вычисляться из `role` — иначе часть шаблонного сьюта краснеет. Это моё, оставляю.

## Чего не учли оба

`uv` и `bun` не установлены, **Docker Desktop не запущен**. Без Postgres нет ни `alembic upgrade`, ни `pytest`, ни «run the app». Python 3.14.7 есть — это единственное, что готово. Первые 15 минут уходят на окружение, а не на код.

## Конфликт CLAUDE.md vs таймбокс — снимаю свою позицию

Я предлагал не вводить юзкейсы. Это противоречит явной инструкции репозитория, а она приоритетнее моих соображений о лаконичности. Делаю ровно три юзкейса, названные в CLAUDE.md (`ListUsers`, `CreateUser`, `UpdateOwnProfile`), и ни одного сверх. Остальные роуты — контроллер + `require(Permission)`, без обвязки.

## Уточнённый план

**0. Окружение** — поднять Docker, `brew install uv bun`, импортировать шаблон `486f054` поверх `main`, сохранив `CLAUDE.md`/`README.md`/`chat-history/`.

**1. L1** `core/domain/rbac.py` — `Role`, `Permission`, `ROLE_PERMISSIONS`, `has()`. Только stdlib. Новая роль = одна строка.

**2. БД** — `role` в `UserBase`, дефолт `MEMBER`; миграция + backfill `is_superuser → admin`. `is_superuser` остаётся в схемах и синхронизируется из `role` **ровно в `crud.create_user`/`crud.update_user`**; в авторизации не участвует нигде.

**3. L2/L3** — `AuthorizationPolicy.require()`, порт `AbstractUserRepository`, `SQLModelUserRepository`, мапперы, три юзкейса. `deps.py` — composition root + фабрика `require(Permission)` с 403 и логом отказа.

**4. Поверхность** — `users.py` (4 гейта + 2 внутренних `is_superuser`), `login.py`, `utils.py`, `items.py` (`ITEM_READ_ANY`), новый `GET /metrics/summary`, `GET /users/me/permissions`. Контроль: `rg is_superuser backend/app` не должен давать ни одного попадания вне `models.py`/`crud.py`.

**5. Фронт** — `generate-client`, `usePermissions()`, `<Forbidden/>` вместо тихого `redirect`, роут `/metrics`, сайдбар по правам, **и перевод `AddUser`/`EditUser`/`columns` на select роли**, чистка мёртвой ветки в `settings.tsx`.

**6. Тесты** — матрица как чистая функция; manager 200 на list / 403 на create; member 403 на metrics; эскалация через `PATCH /users/me` невозможна; `test_architecture.py` (AST). Фикстуры `manager_token_headers`/`member_token_headers` в `conftest.py`, `init_db` выдаёт первому админу `role=ADMIN`.

**7. Сдача** — README (матрица, подход, seed трёх ролей, миграции, тесты), один ADR, `NOTES.md` со срезанным. `git remote add submission git@github.com:jeksman/fullstack-dev-test-task.git` — текущий `origin` смотрит на `evios`.

**Главный риск теперь другой.** Не «две истины» (она закрывается одним `rg`), а **невозможность верифицировать**: без поднятого Docker весь пункт «verify, test and run» превращается в обещание. Если Docker не стартует — честно писать в `NOTES.md`, что прогнаны только юнит-тесты матрицы и AST-тест, а интеграционные не запускались.

Срезаю: второй ADR, диаграмму, E2E на Playwright. Не срезаю: миграцию, security-проверки, инструкции запуска.
