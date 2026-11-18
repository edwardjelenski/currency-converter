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

---

## 7. 2026-11-18 20:56

**Запрос:**

```text
multistage Dockerfile + docker-compose.yml. проверь что docker compose up с нуля поднимается, healthcheck зеленеет, после down/up база на месте. если докер не запущен скажи, сам ничего не ставь
```

**Что сделано:**
- Проверил окружение: Docker не установлен вовсе (нет CLI, Docker Desktop, OrbStack, Colima, Podman,
  Rancher, сокета). Ничего не устанавливал
- `Dockerfile`: build на `swift:6.4-noble` (тег проверен на Docker Hub), отдельный слой `swift package resolve`,
  `--static-swift-stdlib` + jemalloc; run на `ubuntu:noble` с `ca-certificates`, `tzdata`, `curl`,
  пользователь `vapor`, `/data` под volume, `ENV HOST/PORT/DATABASE_PATH/LOG_LEVEL`
- `docker-compose.yml`: именованный volume `rates-data`, healthcheck `curl -f /health`
  (`start_period` 120s под бэкфилл), `LOG_LEVEL=info`, порт через `SERVER_PORT`; `.dockerignore`
- Проверка без Docker: YAML разбирается (ruby); release-сборка на macOS; запуск release-бинарника с командой
  и env контейнера на чистой базе — команда healthcheck даёт `22` (503) во время бэкфилла и `0` после;
  бэкфилл 256 дней; `SIGTERM` завершает процесс сразу с кодом 0; повторный запуск — «up to date, 256 days»
- `scripts/verify-docker.sh` — сквозная проверка (с нуля → healthy → down/up → те же дни в базе)
  в отдельном compose-проекте со своим volume и портом; `shellcheck` чистый
- README (раздел Docker Compose со статусом проверки), architecture (раздел 8, статус плана)

**Не сделано:** реальный `docker compose up` — нужен установленный и запущенный Docker.

**Файлы:** `Dockerfile`, `docker-compose.yml`, `.dockerignore`, `scripts/verify-docker.sh`, `README.md`,
`docs/architecture.md`, `PROMPTS.md`, `REFLECTION.md`, `.agent/*`

**Коммиты:** Add multistage Dockerfile and Compose setup (not yet run in Docker)

---

## 8. 2026-11-18 21:04

**Запрос:**

```text
переводим приложение на наш сервер. HTTPClient + ServerRatesAPI, кэш с ETag и сроком годности, FrankfurterClient удалить совсем чтоб во внешние апи приложение больше не ходило  проверь в симуляторе с сервером из компоуза: холодный старт, повторный запуск без сети (сервер погасить), рефреш с 304
```

**Что сделано:**
- Docker по-прежнему не установлен → сервер для проверки запущен локально (`swift run App serve`,
  тот же код и та же база), а не из Compose — сказал об этом сразу
- iOS: `HTTPClient` + `URLSessionHTTPClient` (без `URLCache`), `RatesAPI` + `ServerRatesAPI` (условный GET,
  ETag, `max-age`, `304`, формат ошибок сервера, курсы строками → `Decimal`), `RatesCache` v2 (ETag, сроки),
  `RatesRepository` (свежий кэш — без запроса, истёк/pull-to-refresh — `If-None-Match`), модель экрана
  (`load` / `refresh` / `refreshIfNeeded` при возврате из фона), адрес сервера из `API_BASE_URL` → Info.plist,
  ATS только для локальных адресов; `FrankfurterClient` и `RatesProviding` удалены, в приложении
  остался один адрес — `http://127.0.0.1:8080`
- Сервер: `AccessLogMiddleware` пишет статус ответа (`→ 304 (If-None-Match)`)
- 41 iOS-тест (мок `HTTPClient`, мок `RatesAPI`, тестовые часы); серверные 52 — без изменений, проходят
- Симулятор (существующий iPhone 17 Pro, выключен после проверки):
  1. холодный старт (приложение удалено) → `GET /rates?base=EUR → 200 (If-None-Match: none)`, курсы на экране
  2. сервер погашен, приложение перезапущено → курсы из кэша, запросов нет (кэш свежий);
     pull-to-refresh → «Could not connect to the server», плашка «Couldn't update rates»
  3. сервер поднят, pull-to-refresh → `304` и в логе приложения, и в логе сервера, плашка исчезла
- Хост unit-тестов больше не запускает загрузку курсов (находка из логов симулятора)
- Скриншоты из симулятора в `docs/screenshots/`, README и architecture обновлены

**Файлы:** `src/ios/**`, `tests/ios/**`, `src/server/App/utils/AccessLogMiddleware.swift`,
`src/server/App/configure.swift`, `.gitignore`, `README.md`, `docs/**`, `PROMPTS.md`, `REFLECTION.md`, `.agent/*`

**Коммиты:** `6f58d7b` Log every request with its final status on the server ·
`daee635` Switch the iOS app to our server; remove the direct Frankfurter client ·
`876fef4` Test the server API client, ETag cache and refresh policy · Document the server-backed iOS client

---

## 9. 2026-11-18 21:20

**Запрос:**

```text
экран истории курса на swift charts. периоды 1Н/1М/3М/1Г, selection драгом со значением на дату, мин/макс и изменение в % за период. как открывать с главного экрана - предложи сам. пустое состояние и ошибку без сети тоже продумай
```

**Что сделано:**
- Вход: карточка курса пары на главном экране («1 USD = 0.9117 EUR · History ›», push-навигация) и
  контекстное меню любой валюты в «Other currencies» → «Rate history»
- Экран: курс и изменение за период в шапке, переключатель 1W/1M/3M/1Y (подписи на английском, как весь
  интерфейс), Swift Charts (линия + заливка), выделение драгом (`chartXSelection`: линия, точка, подсказка
  со значением на день, хаптик), плитки Low/High/Change в `Decimal`, смена пары местами
- Состояния: загрузка, пусто (`no_data` или один день), нет сети без данных («No connection» + «Try Again»),
  нет сети с данными в памяти (график + плашка), ошибка сервера с его текстом
- Данные: `RatesAPI.history` → `GET /timeseries` для одной пары; `RateHistoryRepository` хранит результаты
  в памяти на сессию
- Превью (месяц, год с выделением, пусто, офлайн, загрузка) отрендерены через Xcode MCP; 59 iOS-тестов
- Симулятор с сервером: вход с карточки (`/timeseries … → 200`), 1M/1Y/1W на реальных данных,
  без сети — «No connection» для 3M и график из памяти с плашкой для 1M, вход из контекстного меню (USD→AUD)
- По итогам проверки: подписи оси X больше не обрезаются, на недельном графике отмечены дни публикации,
  повторная загрузка того же периода не мигает индикатором
- README (возможности, скриншоты), architecture (экран истории, таблица состояний, поток 7.5, план)

**Файлы:** `src/ios/CurrencyConverter/{models/RateHistory.swift, services/RatesAPI.swift, services/ServerRatesAPI.swift,
services/RateHistoryRepository.swift, services/RatesRepository.swift, components/history/*, components/converter/ConverterView.swift,
CurrencyConverterApp.swift, preview/PreviewData.swift}`, `tests/ios/*`, `docs/**`, `README.md`, `PROMPTS.md`, `REFLECTION.md`, `.agent/*`

**Коммиты:** `46b85f3` Add rate history screen with Swift Charts · `13040e7` Test rate history model, API and screen states ·
Document the rate history screen

---

## 10. 2026-11-18 21:43

**Запрос:**

```text
на главном хочу кроме основной пары список избранных валют с пересчетом той же суммы. добавлять из пикера, удалять свайпом, порядок драгом. в пикере сверху секция недавних. выбор валют, избранное и последнюю сумму сохраняй между запусками
```

**Что сделано:**
- Главный экран переведён на `List`; «Favorites» заменяет полный список «Other currencies»: сумма в каждой
  избранной валюте, тап — сделать целевой, контекстное меню (история, порядок, удаление), пустое состояние
- Добавление из пикера (режим с галочками и «Done»), удаление свайпом, порядок — перетаскиванием в режиме Edit
- Пикер: секция «Recent» (последние 5), зафиксирована на время показа
- `PreferencesStore` (UserDefaults): сумма, пара, избранное с порядком, недавние; ключи пары и суммы прежние
- 72 iOS-теста, в т.ч. сверка перестановки с эталонным `Array.move` и восстановление после «перезапуска»
- Превью (главный, пустое избранное, пикер) и симулятор с сервером: свайп-удаление, перестановка в Edit,
  выбор целевой валюты, добавление из пикера, «Recent», перезапуск — сумма, пара, порядок избранного и
  недавние на месте (проверено и по plist настроек в контейнере приложения)
- По итогам проверки: галочки в пикере не обновлялись, «Recent» сдвигал строки во время выбора,
  долгое нажатие открывает меню вместо перетаскивания — исправлено/учтено (errors.md #23–#25)

**Файлы:** `src/ios/CurrencyConverter/{services/PreferencesStore.swift, components/converter/*, components/currency-picker/CurrencyPickerView.swift,
preview/PreviewData.swift}`, `tests/ios/{FavoritesTests.swift, ConverterViewModelTests.swift}`, `docs/**`, `README.md`, `PROMPTS.md`,
`REFLECTION.md`, `.agent/*`

**Коммиты:** `cff8ee4` Add favorites with the same amount converted, and recent currencies ·
`690c14e` Test favorites, recents and persistence across launches · Document favorites and recents

---

## 11. 2026-11-18 22:48

**Запрос:**

```text
сумма крупно с monospacedDigit, хаптик на swap, dynamic type до accessibility размеров не ломает верстку, темная тема. сейчас строки на английском захардкожены - переведи на String Catalog, ru + en
```

**Что сделано:**
- Суммы — `largeTitle` rounded с `monospacedDigit`; результат в полный размер, если помещается, иначе
  ужимается (`ViewThatFits`); хаптик `.impact(.medium)` на смену валют (главный экран и история);
  кнопка смены валют — в стеке между карточками, а не оверлеем
- Dynamic Type: адаптивные раскладки на AX-размерах (карточки, строки избранного, заголовок «Избранное»,
  шапка и плитки истории, строки пикера), ограничение значков и осей графика, меньше подписей оси X
- Локализация: `Localizable.xcstrings` (60 строк) и `InfoPlist.xcstrings` («Валюты») с русским переводом;
  строки из кода — через `String(localized:)`/`LocalizedStringResource`; проверено `-exportLocalizations`
  (62 строки, без непереведённых) и тестами `LocalizationTests`
- Инструменты Xcode MCP для каталогов строк не использованы: требуют отсутствующих в сессии skills, а
  `LocalizationPlanner` правит `.xcodeproj`, который генерирует XcodeGen
- Проверка: превью (ru, тёмная, AX3/AX5) и симулятор (ru, тёмная, AX5, домашний экран); найдено и исправлено
  шесть проблем вёрстки на крупных размерах (см. errors.md); тесты сделаны независимыми от языка; 75 iOS-тестов
- Настройки симулятора (язык, тема, размер текста) возвращены к исходным, симулятор выключен

**Файлы:** `src/ios/project.yml`, `src/ios/CurrencyConverter/{resources/*.xcstrings, styles/Theme.swift, components/**, models/RateHistory.swift,
services/RatesAPI.swift, preview/PreviewData.swift}`, `tests/ios/{LocalizationTests.swift, RateHistoryViewModelTests.swift}`,
`README.md`, `docs/**`, `PROMPTS.md`, `REFLECTION.md`, `.agent/*`

**Коммиты:** `295ec9a` Polish the UI: big monospaced amounts, swap haptic, layouts up to AX5 ·
`97f0217` Localize the app into Russian with String Catalogs · `10ccc49` Make tests language-independent and test the Russian bundle ·
Document localization, dark mode and Dynamic Type
