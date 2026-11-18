# ROBOHACK 2.0 / Hackathon Go1 — сдача задания T1

Скаффолд для автоматической проверки T1: Docker-образ `linux/amd64` на Ubuntu 22.04
с исполняемым `/entrypoint.sh`, поддерживающим `ping`, работу без сети, без GPU и без root.

## Что внутри

| Файл | Назначение |
|---|---|
| `Dockerfile` | Образ: ubuntu:22.04, непривилегированный пользователь uid 10001, `/entrypoint.sh` |
| `entrypoint.sh` | Контракт запуска: `ping` → один JSON в stdout + exit 0; `T2..T5` → отказ, пока не реализованы |
| `verify.sh` | Локальная имитация проверки организаторов (6 проверок) |
| `tools/check_ping.py` | Строгий валидатор ответа `ping` по п. 3.3 ТЗ |
| `.gitattributes` | Гарантирует LF в `.sh` (иначе в образе будет `\r: not found`) |

## 1. Правки перед сборкой

Всё, что нужно менять, — блок констант в начале `entrypoint.sh`:

```bash
SUPPORTED_TASKS_JSON='[]'      # реально реализованные задания: '["T2"]', '["T2","T3"]' ...
SELF_TRAINED_RL="false"        # true только при самостоятельном обучении/дообучении RL-политики
PREFERRED_SPEED_MPS="null"     # м/с для T3, null если T3 не реализовано
```

Декларировать нужно только то, что действительно работает: заявленное, но не
запускающееся задание проверяется вызовом `/entrypoint.sh T2|T3|T4|T5`.

## 2. Локальная проверка

```bash
bash verify.sh
```

Проверяются: сборка под `linux/amd64`, платформа образа, исполняемость и права
на `/entrypoint.sh`, корректность и время `ping` без сети, стабильность ответа,
ненулевой код возврата для незаявленных заданий.

## 3. Публикация образа

Нужны Docker Engine, Buildx и учётная запись Harbor от организаторов.

```bash
docker login registry.cookcloud.ru

read -r -p "Имя команды в Harbor: " TEAM_NAME
IMAGE="registry.cookcloud.ru/go1-hackathon-remote-stage-${TEAM_NAME}/${TEAM_NAME}:latest"

docker buildx build --platform linux/amd64 -t "$IMAGE" --push .
docker buildx imagetools inspect "$IMAGE"        # взять строку Digest: sha256:...
```

Проверка, что образ реально скачивается по digest:

```bash
read -r -p "Digest (sha256:...): " DIGEST
FINAL_IMAGE="${IMAGE%:*}@${DIGEST}"
docker pull --platform linux/amd64 "$FINAL_IMAGE"
```

## 4. Что указать в личном кабинете

| Поле | Значение |
|---|---|
| GitHub (конкретный коммит) | `https://github.com/<user>/<repo>/commit/<40-символьный SHA>` |
| Команда загрузки образа | `docker pull --platform linux/amd64 registry.cookcloud.ru/go1-hackathon-remote-stage-<team>/<team>@sha256:<digest>` |

Ссылка на ветку `main` не принимается. Исходники коммита должны совпадать с
собранным образом: перед сборкой `git status --short` должен быть пуст, а
`git rev-parse HEAD` — совпадать с указанным в кабинете.

## Частые причины провала

- `/entrypoint.sh` не исполняем или лежит не в корне — Judge запускает контейнер с
  `--entrypoint /entrypoint.sh`, ENTRYPOINT из Dockerfile игнорируется.
- CRLF в `entrypoint.sh` (правка файла на Windows без `.gitattributes`).
- В stdout при `ping` попадает баннер, `apt`-вывод, `ROS`-логи — допустим только
  JSON; диагностика только в stderr.
- Запуск от root (`USER` не переключён) или образ собран под `linux/arm64`.
- Образ тянет пакеты из сети при старте (`pip install`, `apt-get update` в entrypoint).
- `preferred_speed_mps` строкой (`"0.3"`) вместо числа, или непустой при `T3` вне списка.

## 5. Где собирать образ

**Путь А — Docker Desktop на этой машине.** Нужны WSL 2 и перезагрузка: Docker Desktop
затем `docker login registry.cookcloud.ru`, дальше раздел 3. Сборка под amd64 на
Windows x86 идёт нативно, эмуляция не нужна.

**Путь Б — GitHub Actions, Docker локально не нужен.** В репозитории лежит
`.github/workflows/publish-participant-image.yml`: он собирает образ под `linux/amd64`,
пушит в `registry.cookcloud.ru`, проверяет платформу в манифесте, скачивает образ
обратно по digest и прогоняет `ping` без сети, а в Summary печатает готовые поля для
кабинета (digest, команду `docker pull`, ссылку на коммит).

Подготовка один раз:

```bash
git init && git add -A && git commit -m "T1: participant image"
git branch -M main
git remote add origin https://github.com/<user>/<repo>.git   # репозиторий ПУБЛИЧНЫЙ
git push -u origin main
```

Затем в GitHub: Settings → Secrets and variables → Actions добавить `HARBOR_USERNAME`
и `HARBOR_PASSWORD`, открыть вкладку Actions → `publish-participant-image` → Run
workflow, указать имя команды в Harbor. После прогона взять digest и команду из Summary.

## 6. Чек-лист перед отправкой в кабинет

| # | Проверка | Как убедиться |
|---|---|---|
| 1 | `/entrypoint.sh ping` даёт ровно один JSON, `exit 0`, < 10 с | `verify.sh`, шаги 4–5 |
| 2 | stdout чистый: ни баннеров, ни логов | `docker run ... ping` — глазами |
| 3 | Образ `linux/amd64` | `docker image inspect --format '{{.Os}}/{{.Architecture}}'` |
| 4 | Запуск не от root | `docker run --entrypoint id <img>` → uid 10001 |
| 5 | Работает без сети | шаг 4 `verify.sh` (`--network none`) |
| 6 | Образ тянется по digest у орга | `docker pull --platform linux/amd64 <repo>@sha256:...` на чистой машине |
| 7 | Ссылка на коммит открывается в браузере (инкогнито) | репозиторий публичный |
| 8 | Исходники коммита = собранный образ | `git status --short` пуст перед сборкой |
| 9 | Кабинет заполняет капитан | в ЛК «Публикаций команды: 0 из 3» |

Отправлять заранее: окно исправлений 24 ч, но не позже дедлайна 19 ноя 12:00 МСК.
