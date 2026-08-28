Проверил обе версии по реальному коду шаблона (`/tmp/fst`, актуальный master `486f054`).

## Где он прав, а я ошибся

**1. Репозиторий пуст.** Здесь только `README.md` задания + `CLAUDE.md`. Я писал «переводим роуты на `require()`», как будто код уже в репо. Первый коммит — вендоринг шаблона. Это его находка, забираю.

**2. Целевой remote недоступен.** `origin` = `evios/Fullstack-Dev-Test-Task`, а push нужен в `jeksman/fullstack-dev-test-task` → API отдаёт **404** (не существует или приватный). Блокер на этапе push, не на реализации.

**3. Мой список мест `is_superuser` был неполный.** Я обещал «после правки grep даст две строки плюс модель». Реальный grep:

```
backend/app/api/routes/items.py:21,56,89,109   ← ownership-override, ни он, ни я не упомянули
backend/app/api/routes/users.py:137,172
backend/app/api/deps.py:53
backend/app/core/db.py:31
frontend: AppSidebar, admin.tsx, settings.tsx:28, columns.tsx, AddUser, EditUser
```

`items.py` — 4 места, и `settings.tsx` — вкладка настроек. Митигация «выставлять из `crud`» их не покрывает.

## Чего не учёл он

- **`items.py` и `settings.tsx`** — те же 5 мест. «Оставить `is_superuser`, но не использовать для решений» — декларация без плана; в его списке файлов их нет.
- **`private.py`** создаёт `User(...)` напрямую, минуя `crud`. А `tests-start.sh` гоняет pytest с `FASTAPI_ENV=development` — то есть роут **включён в тестах**. Его «сделать `role` NOT NULL» без default в модели уронит и роут, и весь прогон.
- **`docker-compose.yml` не существует** — в шаблоне `compose.yml` / `compose.override.yml`. Он получил 404 на curl и прошёл мимо; README setup со ссылкой на `docker-compose.yml` не заработает «with first try».
- **Маршрут `/users` на фронте не существует** — в шаблоне `/_layout/admin.tsx`. Guard вешать туда.
- **Пять use case'ов + порты + репозитории + мапперы за час** — против прямого «keep scope tight». `ViewMetricsUseCase` вокруг двух `count(*)` — абстракция ради галочки.

## Уточнённое решение

**Ключевая правка против нас обоих:** `is_superuser` делается **производным на уровне модели**, а не синхронизируемым в `crud`:

```python
class User(UserBase, table=True):
    role: Role = Field(default=Role.MEMBER, max_length=20, index=True)

    @property
    def is_admin(self) -> bool:
        return self.role is Role.ADMIN
```

Дальше `sed`: 8 backend-мест `current_user.is_superuser` → `current_user.is_admin`. Колонка `is_superuser` остаётся в БД и в `UserPublic` (существующие тесты `test_users.py`/`test_login.py`/`test_user.py` не ломаются), но **ни одно решение о доступе её не читает**. Два источника истины сводятся к одному без переписывания CRUD.

Остальное:

| | |
|---|---|
| **L1** | `core/domain/permissions.py`: `Role`, `Permission`, `ROLE_PERMISSIONS`. Новая роль = одна строка. |
| **L2** | `AuthorizationPolicy.require(role, perm)` → `AccessDenied`. Три тонких use case (`ListUsers`/`CreateUser`/`UpdateOwnProfile`) поверх одного порта — их прямо называет `CLAUDE.md`, это ~60 строк. `Metrics` — стаб в роуте без use case. |
| **L3** | `deps.py`: фабрика `require(Permission.X) -> Depends`, логирует отказ (кто/право/ресурс), переводит в 403. Все `Depends(get_current_active_superuser)` → на неё. |
| **Миграция** | `add_column('role', server_default='member')` одной операцией + `UPDATE user SET role='admin' WHERE is_superuser` → `NOT NULL`. Default в модели держит `private.py` живым. |
| **Эскалация** | `role` нет в `UserUpdateMe` и нет в `UserRegister`→`UserCreate` (signup всегда `member`); `private.py` — тоже `member`. Менять роль может только admin через `PATCH /users/{id}`. |
| **Фронт** | `GET /users/me/permissions` → `usePermissions()`/`can()`. Сайдбар, `settings.tsx:28`, `columns.tsx` (бейдж роли вместо Superuser/User), `AddUser`/`EditUser` (select роли). `admin.tsx` + новый `metrics.tsx` в `beforeLoad` рендерят `<Forbidden />` вместо тихого redirect. Manager видит таблицу, но не кнопку Add User. |
| **Тесты** | Матрица параметризованно без БД; `GET /users/` 403 member / 200 manager; `POST /users/` 403 manager / 200 admin; `PATCH /users/me` с `role` роль не меняет; `test_architecture.py` (AST, требование `CLAUDE.md`). |
| **Запуск** | `docker compose up -d` + `bash scripts/test.sh`; seed трёх ролей дописать в `initial_data.py`. |

## Главный риск (уточнён)

Не backfill сам по себе, а **`items.py`**: там `is_superuser` — это не RBAC, а ownership-override («админ видит чужие items»). Перевод его на `is_admin` меняет семантику для manager'а — он перестанет быть суперюзером по items, хотя раньше `is_superuser=True` мог быть выставлен вручную. Поведение корректное, но это правка за пределами заявленной поверхности задания — надо назвать её явно в `NOTES.md`, а не протащить молча.

**Вопрос, который надо решить до push:** `jeksman/fullstack-dev-test-task` отдаёт 404. Создать через `gh repo create` под твоим аккаунтом, или репо приватный и нужен доступ?
