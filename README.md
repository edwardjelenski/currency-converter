# Currency Converter

Мобильное приложение-конвертер валют (iOS) с собственной серверной частью.
Учебный проект: разработка с ИИ-агентом, ход работы задокументирован в
[PROMPTS.md](PROMPTS.md), [REFLECTION.md](REFLECTION.md) и [.agent/](.agent).

**Тип проекта:** мобильное приложение с серверной частью (клиент-сервер, REST API).

## Возможности

- Конвертация между ~30 валютами по референсным курсам ЕЦБ
- Смена валют местами, поиск валюты по названию или ISO-коду
- Сумма сразу во всех остальных валютах; тап по строке делает валюту целевой
- Работа офлайн с последними загруженными курсами, pull-to-refresh
- Запоминание последней суммы и пары валют
- Ввод суммы с учётом локали: `1 234,5`, `1,234.5`, `1.234,5`

## Стек

| Часть | Технологии |
|---|---|
| iOS-клиент | Swift 6 (strict concurrency), SwiftUI, Observation, iOS 17+, XcodeGen, Swift Testing |
| Сервер | Swift 6, Vapor 4, Fluent + SQLite, обновление курсов по расписанию; REST с ETag/Cache-Control — *в разработке* |
| Инфраструктура | Docker Compose (сервер + volume с БД) — *в разработке* |

Целевая схема: приложение обращается **только к нашему серверу**, сервер сам забирает курсы
у внешнего источника (Frankfurter / ЕЦБ) и хранит их в SQLite.
Сейчас, до появления сервера, клиент временно ходит во Frankfurter напрямую.
Подробнее — [docs/architecture.md](docs/architecture.md).

## Структура

```
.
├── README.md, PROMPTS.md, REFLECTION.md
├── Package.swift                манифест SwiftPM сервера
├── src/
│   ├── ios/                     iOS-клиент
│   │   ├── project.yml          спецификация XcodeGen (.xcodeproj не коммитится)
│   │   └── CurrencyConverter/
│   │       ├── CurrencyConverterApp.swift   точка входа
│   │       ├── components/      SwiftUI-экраны и view
│   │       ├── services/        работа с API и кэшем
│   │       ├── models/          модели данных
│   │       ├── utils/           вспомогательные функции
│   │       ├── styles/          цвета, шрифты, размеры (Theme)
│   │       ├── resources/       Assets.xcassets
│   │       └── preview/         тестовые данные для #Preview (только Debug)
│   └── server/App/              сервер: entrypoint, services/, models/, migrations/, utils/
├── tests/
│   ├── ios/                     unit-тесты клиента (Swift Testing)
│   └── server/                  тесты сервера (Swift Testing)
├── docs/
│   ├── architecture.md          схема компонентов
│   └── screenshots/             скриншоты
└── .agent/                      артефакты работы с ИИ-агентом
    ├── prompt-log.md            хронология запросов
    ├── errors.md                ошибки агента и их исправление
    └── config.json              настройки агента
```

**Про `package.json` / `requirements.txt`.** В Swift их роль играет манифест
SwiftPM `Package.swift`. Для сервера он лежит **в корне репозитория**:
SwiftPM не разрешает пакету ссылаться на исходники вне своей папки, а тесты по
шаблону лежат в `tests/server`, поэтому корень — единственное место, откуда
видны и `src/server`, и `tests/server`. У iOS-клиента сторонних зависимостей нет,
его настройки сборки описаны в `src/ios/project.yml`. Отдельный `requirements.txt`
(формат Python) в проекте не нужен.

## Запуск

### iOS-клиент

Нужны Xcode 16+ и XcodeGen.

```bash
brew install xcodegen
cd src/ios
xcodegen generate
open CurrencyConverter.xcodeproj
```

`.xcodeproj` генерируется из `project.yml` — перегенерируйте его после `git pull` и
после добавления или удаления файлов.

Тесты — в Xcode (⌘U) или из `src/ios`:

```bash
xcodebuild test -project CurrencyConverter.xcodeproj -scheme CurrencyConverter -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

### Сервер

Нужен Swift 6 (Xcode 16+ на macOS или Swift toolchain на Linux). Из корня репозитория:

```bash
swift run App serve
```

При первом запуске сервер создаёт `data/rates.sqlite`, загружает курсы за последний год
и дальше обновляет их сам по будням после публикации ЕЦБ. В логе это выглядит так:

```text
[ INFO ] Sync (startup) started: backfill 2025-11-18...2026-11-18
[ INFO ] Stored 30 currencies
[ INFO ] Sync (startup) finished: backfill added 256 days (2025-11-18...2026-11-18), 7454 rates; 256 days in DB, latest 2026-11-18
[ INFO ] Next sync at 2026-11-19 16:15 Europe/Berlin
```

После перезапуска сервер догружает только пропущенные дни.

| Переменная | По умолчанию | |
|---|---|---|
| `DATABASE_PATH` | `data/rates.sqlite` | файл SQLite |
| `BACKFILL_DAYS` | `365` | глубина истории при первом запуске |
| `SYNC_TIME` | `16:15` | первая попытка обновления, Europe/Berlin |
| `SYNC_ENABLED` | `true` | фоновое обновление курсов |
| `UPSTREAM_BASE_URL` | `https://api.frankfurter.dev/v1/` | источник курсов |
| `HOST`, `PORT` | `127.0.0.1`, `8080` | |

Тесты сервера:

```bash
swift test
```

REST API и запуск через `docker compose up` — следующие шаги, см. [docs/architecture.md](docs/architecture.md#10-текущее-состояние-и-план).

## Скриншоты

| Светлая тема | Тёмная тема |
|---|---|
| ![](docs/screenshots/converter-light.png) | ![](docs/screenshots/converter-dark.png) |

Видео-демонстрация (`docs/demo.mp4`) будет добавлена после подключения сервера.
