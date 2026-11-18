# Хронология запросов к агенту

Каждый запрос к агенту записывается дословно, с датой и кратким итогом: что сделано,
какие файлы затронуты, какие коммиты. Запись добавляет сам агент в конце каждого ответа
(правило в [CLAUDE.md](../CLAUDE.md)). Разбор ключевых промптов — в [PROMPTS.md](../PROMPTS.md).

---

## 1. 2026-11-18 ~19:40

**Запрос:**

```text
создай новый ios проект - конвертер валют. swiftui, ios 17+, swift 6 со strict concurrency. проект генерь через xcodegen (project.yml в репе, .xcodeproj в gitignore), bundle id com.eduardyelenskiy.currencyconverter

создай публичную репу через gh cli (я залогинен), добавь какой нибудь самый популярный .gitignore под ios проект. дальше по ходу работы коммить в main осмысленными коммитами и пушь
```

**Что сделано:**
- Проверил окружение: xcodegen 2.46, gh (авторизован), Xcode 27, свободные симуляторы
- Создал публичный репозиторий `currency-converter`, `.gitignore` — шаблон GitHub `Swift.gitignore` + `*.xcodeproj`
- `project.yml`: iOS 17, Swift 6, `SWIFT_STRICT_CONCURRENCY = complete`, таргет тестов на Swift Testing
- Слой данных: `ExchangeRates` (кросс-курсы от EUR), `FrankfurterClient`, `RatesCache` (actor), `RatesRepository`
- UI: `ConverterView`, `ConverterViewModel` (@MainActor @Observable), `CurrencyPickerView`, превью с моковыми данными
- Отрендерил превью через Xcode MCP (светлая/тёмная тема, пустое состояние)
- 21 unit-тест; падение теста на немецкой локали → вынес разбор суммы в `AmountParser` (см. errors.md #1)

**Файлы:** `.gitignore`, `README.md`, `project.yml`, `CurrencyConverter/**`, `CurrencyConverterTests/**`

**Коммиты:** `d01c4e6` Add Swift .gitignore and README · `f644e37` Add XcodeGen project skeleton ·
`8dbef35` Add exchange rates models and data layer · `ba994ef` Add converter screen and currency picker ·
`24aa60c` Add AmountParser and unit tests · `2f97fcb` Document features, setup and architecture in README

---

## 2. 2026-11-18 ~20:00

**Запрос:**

```text
забыл скинуть требования - это проект для зачета, вот задание:

## Тип проекта:
- Мобильное приложение (Android/iOS/кроссплатформенное) с серверной частью
- Информационная система для организации (учёт, документооборот, аналитика)
- Сервис обработки и визуализации данных (дашборды, отчёты)
- Клиент-серверное приложение с REST API и авторизацией
- Решение с элементами машинного обучения (классификация, рекомендации, прогнозирование)
- Инструмент автоматизации (парсер, бот, CLI-утилита) с обоснованием применимости
- Нужен докер компоуз 

## Примерная структура проекта:
project-root/:
- README.md - Описание проекта, стек, инструкция запуска
- PROMPTS.md - Дневник промптов (ключевой артефакт!)
- REFLECTION.md - Рефлексия: что удалось/не удалось агенту
- .gitignore
- package.json - или requirements.txt / pubspec.yaml
- src/ - Исходный код приложения
  - main.js/.py/.rs/.dart/.swift/.kt - Точка входа
  - components/ - UI-компоненты
  - services/ - Логика, работа с API/БД
  - utils/ - Вспомогательные функции
  - styles/ - Стили
- tests/ - Тесты
  - app.test.js
- docs/
  - screenshots/ - Скриншоты работающего приложения
  - architecture.md - Схема компонентов
  - demo.mp4 - Видео-демонстрация (30-60 сек)
- .agent/ - Папка для артефактов работы с ИИ
  - prompt-log.md - Хронология всех запросов к агенту
  - errors.md - Ошибки агента и способы их исправления
  - config.json - Настройки агента (модель, режим, tools)

я делаю мобилку+сервер
- делаем свой бэк на swift, sqlite, rest. приложение ходит только в наш бэк, во внешние апи напрямую нет
- раскладка как в шаблоне: ios проект переедет в src/ios (project.yml + исходники, внутри разложи по components/services/utils по смыслу), бэк в src/server, тесты в tests/ios и tests/server. requirements.txt в корне как в шаблоне или рядом с сервером - подумай что логичнее
- добавь заглушки README, PROMPTS.md, REFLECTION.md, docs/ (screenshots, architecture.md), .agent/ (prompt-log.md, errors.md, config.json)

перенеси то что уже есть, поправь пути в project.yml, убедись что xcodegen generate и сборка проходят. закоммить и запушь
```

**Что сделано:**
- Перенёс клиент в `src/ios` через `git mv` (история сохранена), тесты — в `tests/ios`
- Разложил исходники по `components/ services/ models/ utils/ styles/ resources/ preview/`;
  `CurrencyCard`, `ConversionRow`, `OfflineBanner` вынесены из `ConverterView` в отдельные файлы,
  цвета/радиусы/шрифты — в `styles/Theme.swift`
- `project.yml`: путь тестов `../../tests/ios`; `xcodegen generate`, сборка и 21 тест проходят
- Проверил на тестовом пакете, что SwiftPM не принимает тесты вне корня пакета →
  `Package.swift` сервера будет в корне, `requirements.txt` не нужен
- Написал README (рус.), PROMPTS.md, REFLECTION.md, `docs/architecture.md`, скриншоты из превью,
  `.agent/*`, заглушки `src/server`, `tests/server`

**Файлы:** `src/ios/**`, `tests/ios/**`, `README.md`, `PROMPTS.md`, `REFLECTION.md`, `docs/**`,
`.agent/**`, `src/server/README.md`, `tests/server/.gitkeep`

**Коммиты:** `c78af68` Move iOS client to src/ios and tests to tests/ios ·
`1bb3a6e` Add course docs and AI agent artifacts

---

## 3. 2026-11-18 20:13

**Запрос:**

```text
насчет .agent:
- prompt-log.md - после каждого моего сообщения дописывай дословно запрос, дату и коротко что сделано (файлы, коммит)
- errors.md - каждый раз когда что-то пошло не так с твоей стороны (не собралось, тест упал, не так понял задачу): что было, причина, как исправил
- config.json - модель, режим, какие тулы и mcp реально используются

этот и два предыдущих запроса тоже залогируй
```

**Что сделано:**
- Переписал этот лог: запросы 1–3 дословно, с датой, итогом, файлами и коммитами
- Дополнил `errors.md` всеми сбоями агента в формате «что было / причина / как исправил»
  (добавлены ошибки shell в zsh; проверка SwiftPM убрана — это была проверка гипотезы, а не ошибка)
- `config.json`: только реально использованные инструменты, MCP и CLI
- Добавил `CLAUDE.md` с правилами ведения `.agent/`, чтобы агент соблюдал их в каждом ответе
  и в новых сессиях

**Файлы:** `.agent/prompt-log.md`, `.agent/errors.md`, `.agent/config.json`, `CLAUDE.md`, `REFLECTION.md`

**Коммиты:** Log every agent request and error in .agent

---

## 4. 2026-11-18 20:16

**Запрос:**

```text
архитектура:

- бэк: /currencies, /rates?base=, /timeseries?base=&symbols=&start=&end=. обновление курсов по расписанию (ECB публикует раз в день по будням), история в sqlite, ETag/Cache-Control чтоб клиент не тянул лишнее
- ios: @Observable вьюмодели, сетевой слой за протоколом чтоб мокать, деньги только Decimal, оффлайн кеш последнего ответа
- кросс курсы считать на клиенте от одной базы или на бэке - предложи и обоснуй

оформи в docs/architecture.md, схема компонентов на mermaid + потоки данных
```

**Что сделано:**
- Проверил у Frankfurter: таймсерия за год отдаётся по дням (256 рабочих дней) одним запросом,
  в ответах есть `ETag` и `Cache-Control` — на этом построены бэкфилл и условные запросы сервера
- Переписал `docs/architecture.md`: схема компонентов, сравнение вариантов расчёта кросс-курсов
  и решение (гибрид: сервер умеет `base`, конвертер считает от EUR на клиенте, история — на сервере),
  контракт REST API с ошибками, политика ETag/Cache-Control, сервер (Vapor + Fluent + SQLite,
  схема БД, расписание 16:15 Europe/Berlin с повторами), iOS (протоколы `HTTPClient`/`RatesAPI`,
  Decimal, офлайн-кэш с ETag), 5 потоков данных, Docker Compose, тесты, план работ
- Все 7 mermaid-диаграмм проверил рендером mermaid 11 в браузере; схему компонентов
  перестроил сверху вниз, чтобы она читалась на ширине GitHub
- README: обновлены строки стека сервера и инфраструктуры

**Файлы:** `docs/architecture.md`, `README.md`, `.agent/prompt-log.md`, `.agent/errors.md`, `.agent/config.json`

**Коммиты:** Design client-server architecture in docs/architecture.md

---

## 5. 2026-11-18 20:31

**Запрос:**

```text
архитектура ок, гибрид с кросс курсами поддерживаю, свой планировщик вместо Queues+redis тоже. одна правка: /health пусть отдает не просто ok а дату последних курсов и статус последнего синка - пригодится для healthcheck в компоузе и на демо

начинай сервер, пункт 1 из плана: Package.swift в корне, vapor + fluent sqlite, миграции, RatesSyncService с бэкфиллом за год и догрузкой пропущенных дней, SyncScheduler. источник за протоколом UpstreamRatesSource. подними локально и покажи по логам что бэкфилл прошел и сколько дней легло в базу
```

**Что сделано:**
- `docs/architecture.md`: расширил `/health` (дата последних курсов, число дней в базе, последний синк
  с триггером/статусом/ошибкой, время следующего синка; `ok` / `degraded` / `not_ready` и HTTP-коды
  для healthcheck), обновил поток 7.1 и схему `sync_runs`
- Проверил окружение: Vapor 5 ещё в бете → взят Vapor 4.122; Frankfurter отвечает 404 на диапазон
  без публикаций и иногда 522 → в источнике 404 = «нет данных», 5xx/429/сетевые ошибки — повтор
- `Package.swift` в корне (Vapor, Fluent, FluentSQLiteDriver, NIOCore), миграции `currencies`,
  `rates` (ключ `date+currency`, курс как TEXT, индекс `currency+date`), `sync_runs`
- `UpstreamRatesSource` + `FrankfurterSource`, `RatesStore` (upsert через SQLKit),
  `RatesSyncService` (бэкфилл / догрузка / ежедневное обновление одним путём, журнал в `sync_runs`),
  `SyncSchedule` + `SyncScheduler` (старт, будни 16:15 Berlin, повторы до 19:00), `AppConfig` из env
- 22 теста сервера (Swift Testing, SQLite в памяти, заглушка источника) — проходят
- Запуск локально с пустой базой: бэкфилл добавил **256 дней** (2025-11-18…2026-11-18),
  7454 курса, 30 валют, WAL. Проверка догрузки: удалил 3 последних дня, перезапустил —
  сервер запросил только 2026-11-14…2026-11-18 и добавил 3 дня
- README: запуск сервера, переменные окружения, пример лога; architecture: структура, BGN, статус плана

**Файлы:** `Package.swift`, `Package.resolved`, `.gitignore`, `src/server/App/**`, `tests/server/**`,
`docs/architecture.md`, `README.md`, `PROMPTS.md`, `REFLECTION.md`, `.agent/*`

**Коммиты:** `7ddf81a` Add Vapor server with SQLite storage and scheduled rates sync ·
`1bc83ab` Add server tests for sync, schedule and dates · Document server sync step and /health

---

## 6. 2026-11-18 20:44

**Запрос:**

```text
/currencies /rates /timeseries /health + HTTPCachingMiddleware, ошибки в едином формате как в architecture.md

тесты в tests/server на VaporTesting, sqlite в памяти: ответы эндпоинтов, 400 на кривые параметры, ETag/304, Cache-Control, синк (бэкфилл, праздники когда ECB не публикует, upstream упал или отдал мусор - данные не затираются), расписание с подменой часов включая переход на летнее время. после тестов проверь курлами вживую, с If-None-Match тоже
```

*(Сообщение начиналось с `/currencies` — в приложении это попыталось сработать как slash-команда, её нет; агент воспринял текст как обычный запрос.)*

**Что сделано:**
- REST API: `RatesService` (точные курсы к EUR, кросс-курсы в `Decimal` с округлением до 6 значащих цифр,
  откат на предыдущий день публикации, пропуск дней без базовой валюты), контроллеры `/currencies`,
  `/rates`, `/timeseries`, `/health`
- Единый формат ошибок `APIErrorMiddleware` (вместо стандартного Vapor), коды `invalid_parameter`,
  `unknown_currency`, `no_data`, `not_ready`, `not_found`; ошибки `no-store`
- `HTTPCachingMiddleware`: сильный ETag из SHA-256 тела, `304` на `If-None-Match` (список, `W/`, `*`);
  `Cache-Control` по маршруту; JSON с отсортированными ключами, чтобы ETag был стабильным
- Синк: проверка данных источника до записи (один плохой день отклоняет пакет), `FrankfurterSource`
  отбрасывает только дни до начала диапазона; планировщик принимает функцию `sleep` для тестов
- 52 теста (VaporTesting, SQLite в памяти): эндпоинты, 400/404/503, ETag/304, Cache-Control, мусор и сбои
  источника через заглушку HTTP-клиента, цикл планировщика на подменённых часах (оба перехода
  на летнее время, Пасха), Рождество при догрузке
- Проверка вживую `curl`: `/health`, `/currencies` (30 валют, без BGN, с EUR), `/rates` → ETag → `304`
  (в т.ч. с `W/`), устаревший ETag → `200`, `/rates?base=USD` совпал с тестами, воскресенье → пятница,
  `/timeseries` + `304`, год USD→JPY = 256 дней, 9 ошибочных запросов в едином формате
- README: раздел REST API с живыми примерами; architecture: `/health`, проверка данных источника, статус плана

**Файлы:** `Package.swift`, `Package.resolved`, `src/server/App/**`, `tests/server/**`, `README.md`,
`docs/architecture.md`, `PROMPTS.md`, `REFLECTION.md`, `.agent/*`

**Коммиты:** `79f303e` Add REST API: /currencies, /rates, /timeseries, /health ·
`9e23776` Reject implausible upstream data and make the scheduler clock injectable ·
`863589f` Test endpoints, HTTP caching, upstream failures and schedule · Document REST API step
