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
