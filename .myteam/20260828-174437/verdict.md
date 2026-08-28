Проверил спорные факты сам: Docker не запущен, `uv`/`bun` не установлены, Python 3.14.7 есть; `settings.tsx:28` — действительно мёртвая ветка (обе даёт те же 3 таба); `private.py` без авторизации; в `conftest.py` только `superuser_token_headers` и `normal_user_token_headers`.

## Согласны оба

Единая таблица `Role`/`Permission`/`ROLE_PERMISSIONS`; колонка `role` + Alembic-миграция с backfill из `is_superuser`; фабрика `require(Permission)` в `deps.py` с 403 и логом отказа; `GET /users/me/permissions` как источник прав для фронта; `<Forbidden/>` вместо тихого redirect; `/metrics` заглушка; запрет эскалации через `PATCH /users/me` и `/signup`; перегенерация TS-клиента; README с матрицей + один ADR; push в `jeksman/...` (текущий `origin` — `evios`). Главный риск оба называют одинаково: остаточные `is_superuser`-ветки. Контроль `rg is_superuser` — рабочий и дешёвый.

## Расхождения

**1. Объём Clean Architecture.** Claude сначала предлагал урезать, потом снял позицию. Codex настаивает на полном CA + порт метрик + use case метрик. Сильнее Claude во второй редакции: `CLAUDE.md` называет ровно три юзкейса (`ListUsers`, `CreateUser`, `UpdateOwnProfile`) — их и делать. Порт репозитория для заглушки метрик — выдумка сверх инструкции, три числа считаются в контроллере.

**2. Судьба `is_superuser` в схемах.** Codex: убрать из DTO. Claude: оставить в `UserPublic`, синхронизировать из `role` в `crud`. Прав Claude — и он единственный подкрепил это фактом: `test_users.py`, `conftest.py` и `tests/utils/user.py` построены на этом поле, удаление красит часть апстримного сьюта без всякой выгоды. Поле остаётся, но в авторизации не участвует нигде.

**3. `private.py`.** Claude сперва ошибся (написал, что там есть superuser-гейт), потом честно забрал слова. Codex называет его «дырой». Не правы оба: роут подключается только при `FASTAPI_ENV == "development"`, это апстримный тестовый хук, и после миграции он создаёт юзера с дефолтом `MEMBER`. Трогать нечего — достаточно убедиться, что дефолт роли применяется.

**4. Полнота фронта.** Claude нашёл `AddUser.tsx`, `EditUser.tsx`, `columns.tsx`, мёртвую ветку в `settings.tsx`; Codex это забрал. Здесь Claude сильнее: без перевода этих трёх файлов на select роли admin физически не сможет выдать роль через UI.

**5. Переименование `/admin` → `/users`.** Идея Codex логична (manager видит список, но не управляет), но тянет `routeTree.gen.ts` и не даёт ничего сверх правильного гейтинга. Оставить `/admin`, гейтить страницу по `USER_LIST`, кнопки — по `USER_CREATE`/`USER_UPDATE_ANY`.

**6. Число тестов.** Codex прав по букве `CLAUDE.md` (allowed/denied на каждый защищённый эндпоинт), Claude прав по духу задания (5 штук). Снимается параметризацией: одна таблица `(роль, метод, путь, статус)` — покрытие полное, кода меньше, чем у пяти отдельных тестов.

**7. Чего не увидел Codex вовсе.** Окружения нет. Без Docker весь пункт «verify, test and run» — обещание. Это важнее обеих архитектурных дискуссий, и заметил это только Claude.

## План

1. **Окружение (блокер).** Запустить Docker Desktop, `brew install uv bun`. Не поднялось — вся верификация сводится к юнит-тестам матрицы и AST-тесту, и это пишется в `NOTES.md` прямым текстом.
2. **Импорт шаблона** `486f054` поверх `main`, сохранив `CLAUDE.md`, `README.md`, `chat-history/`.
3. **L1** `core/domain/rbac.py`: `Role`, `Permission`, `ROLE_PERMISSIONS`, `has()`. Только stdlib.
4. **БД**: `role` в `UserBase` (дефолт `MEMBER`, CHECK на допустимые значения), миграция + backfill `is_superuser → admin`. `is_superuser` синхронизируется из `role` ровно в `crud.create_user`/`crud.update_user`.
5. **L2/L3**: `AuthorizationPolicy`, порт `AbstractUserRepository` + SQLModel-реализация, мапперы, три юзкейса из `CLAUDE.md`. `deps.py` — composition root + `require(Permission)`.
6. **Поверхность**: `users.py` (4 гейта + `delete_user_me`, `read_user_by_id`), `login.py:102`, `utils.py:13`, `items.py` (4 места), новые `GET /metrics/summary` и `GET /users/me/permissions`. Приёмка: `rg is_superuser backend/app` — попадания только в `models.py` и `crud.py`.
7. **Фронт**: `generate-client`, `usePermissions()`/`can()`, `<Forbidden/>`, роут `/metrics`, сайдбар по правам, `AddUser`/`EditUser`/`columns` на select роли, чистка мёртвой ветки `settings.tsx:28`.
8. **Тесты**: матрица как чистая функция, параметризованный allowed/denied по эндпоинтам, антиэскалация через `PATCH /users/me`, `test_architecture.py` (AST). Фикстуры `manager_token_headers`/`member_token_headers`, `init_db` даёт первому админу `role=ADMIN`.
9. **Сдача**: README (матрица, 3 абзаца, seed трёх ролей, миграции, `bash scripts/test.sh`), один ADR, `NOTES.md` со срезанным, `git remote add submission`, push.

Срезано: второй ADR, диаграмма, Playwright E2E, переименование `/admin`. Не срезано: миграция, security-гейты, инструкции запуска.
