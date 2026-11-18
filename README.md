# Hackathon Go1 / ROBOHACK 2.0 — задание T1

Решение задания **T1 «Подготовка сдачи решения»**: самодостаточный Docker-образ, который
организаторы запускают на своей инфраструктуре командой `/entrypoint.sh ping` и получают
JSON со сведениями о решении.

T1 — не задача про робота, а контракт запуска и гейт: без него остальные задания не
оцениваются. Проверяется по трём критериям (по 1 баллу):

| Критерий | Что требуется |
|---|---|
| Доступность образа | образ `linux/amd64` скачивается по `sha256` digest |
| `/entrypoint.sh ping` | ≤ 10 с, код возврата 0, в stdout ровно один корректный JSON |
| Автономность | работа без интернета, без доустановки зависимостей, без прав root |

## Соответствие требованиям ТЗ 3.1

| Требование | Как выполнено |
|---|---|
| Архитектура `linux/amd64` | сборка `docker buildx build --platform linux/amd64` |
| Ubuntu 22.04 LTS (Jammy) | база `ros:humble-ros-base` — это Ubuntu 22.04 |
| ROS 2 Humble Hawksbill | `ros:humble-ros-base` (ROS 2 Humble + colcon/rosdep) |
| Eclipse Cyclone DDS, `rmw_cyclonedds_cpp` | пакет `ros-humble-rmw-cyclonedds-cpp` |
| Только CPU, без GPU | нет CUDA/OpenGL-зависимостей |
| Запуск без прав root | `USER participant` (uid 10001) |
| Интернет недоступен во время испытаний | всё запечено в слои; рантайм ничего не тянет |
| Исполняемый `/entrypoint.sh` | `COPY entrypoint.sh /entrypoint.sh` + `chmod 0755` |

## Состав репозитория

| Файл | Назначение |
|---|---|
| `Dockerfile` | образ: ROS 2 Humble на Ubuntu 22.04, RMW Cyclone DDS, uid 10001, `/entrypoint.sh` |
| `entrypoint.sh` | контракт запуска: `ping` → один JSON в stdout + `exit 0`; `T2…T5` → честный отказ |
| `verify.sh` | локальная имитация проверки организаторов, блоки 0–6 |
| `tools/check_ping.py` | строгий валидатор ответа `ping` по п. 3.3 ТЗ |
| `publish.sh` | сборка → push → digest → `docker pull` по digest → `ping` |
| `.gitattributes` | `*.sh text eol=lf` — иначе на Windows в образ попадёт CRLF |
| `.dockerignore` | не пускает в контекст сборки `tools/`, обвязку скриптов и `.git` |
| `.github/workflows/publish-participant-image.yml` | резервная публикация через GitHub Actions (без локального Docker) |

## Быстрый старт

```bash
docker login registry.cookcloud.ru      # учётка от организаторов
bash verify.sh                          # блоки локальных проверок 0–6
bash publish.sh <team>                  # сборка + публикация + digest
```

`publish.sh` в конце печатает готовые поля для личного кабинета.

## Контракт `ping` (п. 3.3 ТЗ)

```json
{"protocol_version":"1.0","supported_tasks":[],"self_trained_rl":false,"preferred_speed_mps":null}
```

| Поле | Тип | Значение |
|---|---|---|
| `protocol_version` | string | ровно `"1.0"` |
| `supported_tasks` | array[string] | только реально работающие задания: `T2`, `T3`, `T4`, `T5` (латинская `T`) |
| `self_trained_rl` | boolean | `true` только при самостоятельном обучении/дообучении RL-политики |
| `preferred_speed_mps` | number \| null | скорость для T3 в м/с; `null`, если T3 не реализовано |

Правила, которые легко нарушить: код возврата `0`, не более 10 с реального времени,
в stdout **ровно один** JSON-объект (пробельные символы допустимы), диагностика — только
в stderr.

## Что менять перед сборкой

Всё настраивается блоком констант в начале `entrypoint.sh`:

```bash
SUPPORTED_TASKS_JSON='[]'      # '["T2"]', '["T2","T3"]' — только работающее
SELF_TRAINED_RL="false"        # true только при собственной обученной политике
PREFERRED_SPEED_MPS="null"     # число м/с для T3, иначе null
```

Заявленное задание проверяется вызовом `/entrypoint.sh T2|T3|T4|T5`, поэтому декларировать
нужно только то, что действительно запускается.

## Проверка

```bash
bash verify.sh                            # собрать и проверить
IMAGE=... IMAGE_READY=1 bash verify.sh    # проверить уже собранный образ
```

| Блок | Что проверяется |
|---|---|
| 0 | LF в `entrypoint.sh`, наличие `.gitattributes` с `eol=lf` |
| 1 | сборка под `linux/amd64` |
| 2 | платформа образа, `PRETTY_NAME` = Ubuntu 22.04 |
| 3 | `/entrypoint.sh` исполняем, uid ≠ 0, внутри образа файл без CRLF |
| 4 | `ping` без сети: код 0, JSON по схеме, время < 10 с |
| 5 | пять запусков `ping` дают одинаковый непустой ответ |
| 6 | незаявленные `T2…T5` завершаются ненулевым кодом, stdout пуст, причина в stderr |

Блок 6 отличает отказ решения от ошибки запуска контейнера: код ≥ 125 или `docker: Error`
в stderr считаются провалом, а не «честным отказом».

Ручные проверки:

```bash
docker run --rm --network none --entrypoint /entrypoint.sh go1-participant:verify ping
docker image inspect --format '{{.Os}}/{{.Architecture}}' go1-participant:verify
docker run --rm --network none --entrypoint /bin/sh go1-participant:verify -c 'id -u'
```

## Публикация

`publish.sh` делает всё по порядку и отказывается работать, если `git status` грязный
(иначе исходники коммита разойдутся с образом):

```bash
bash publish.sh burmalda
```

Что он выполняет: проверка git → `buildx build --platform linux/amd64 --provenance=false
--push` → проверка `platform: linux/amd64` в опубликованном манифесте → получение digest →
`docker pull` по digest → `ping` из скачанного образа.

Ручной вариант:

```bash
IMAGE="registry.cookcloud.ru/<team>/<team>:latest"
docker buildx build --platform linux/amd64 --provenance=false -t "$IMAGE" --push .
docker buildx imagetools inspect "$IMAGE"                  # Digest: sha256:...
docker pull --platform linux/amd64 "${IMAGE%:*}@sha256:..."
```

`--provenance=false` убирает attestation-манифест: без него digest указывает на index с
двумя записями, а не на сам образ.

## Что указать в личном кабинете

| Поле | Значение |
|---|---|
| GitHub (конкретный коммит) | `https://github.com/<user>/<repo>/commit/<40-символьный SHA>` |
| Команда загрузки образа | `docker pull --platform linux/amd64 registry.cookcloud.ru/<team>/<team>@sha256:<digest>` |

Ссылка на ветку не принимается: она изменяема. Публикует только капитан команды, на этап
даётся 3 публикации. Окно исправлений — 24 ч, но не позже жёсткого дедлайна.

## Запуск из Windows-оболочек (MSYS2 / Git Bash / UCRT64)

MSYS2 и Git Bash переводят аргументы, начинающиеся с `/`, в виндовые пути, и
`docker run --entrypoint /entrypoint.sh` падает с
`exec: "E:/Git/entrypoint.sh": no such file or directory`. `verify.sh` и `publish.sh`
отключают это сами:

```bash
export MSYS_NO_PATHCONV=1 MSYS2_ARG_CONV_EXCL='*' MSYS2_ENV_CONV_EXCL='*'
```

При ручных командах добавляйте эти переменные или работайте из PowerShell/cmd.

## Ключевые решения и их причины

| Решение | Причина |
|---|---|
| JSON печатается `printf`, без python/jq | нет зависимостей — нечему упасть без сети |
| константы вынесены в начало скрипта | единственное место правки, остальное — шаблон |
| отказ для `T2…T5` с кодом 64 | `EX_USAGE`: stdout пуст, причина в stderr — отказ виден и диагностируем |
| `set +u` вокруг `source setup.bash` | ROS 2 `setup.bash` несовместим с `nounset` и падает на `AMENT_TRACE_SETUP_FILES` |
| `USER participant` (uid 10001) | требование «без прав root» |
| конфиг DDS в образе не прописывается | `ROS_DOMAIN_ID`, `RMW_IMPLEMENTATION`, `CYCLONEDDS_URI` передаёт лаунчер организаторов |
| `.gitattributes` с `eol=lf` | иначе правка на Windows приносит CRLF в исполняемый скрипт |
| `--provenance=false` | digest должен указывать на образ, а не на index с attestation-манифестом |

## Частые причины провала

| Симптом | Причина |
|---|---|
| `\r: not found` при старте | CRLF в `/entrypoint.sh` |
| `/entrypoint.sh` не найден | файл не в корне или не исполняем: Judge задаёт `--entrypoint /entrypoint.sh` и игнорирует `ENTRYPOINT` из Dockerfile |
| В stdout баннер, лог ROS или вывод `apt` | посторонний текст ломает JSON-парсер |
| `platform = linux/arm64` | образ собран без `--platform linux/amd64` |
| Работает от root | не переключён `USER` |
| Тянет пакеты при старте | `pip install` / `apt-get update` в `entrypoint.sh` — без сети это провал |
| `preferred_speed_mps` строкой | требуется число (`0.3`), не `"0.3"` |
| `manifest unknown` при `pull` | digest скопирован не целиком |
| Ссылка на коммит 404 | репозиторий приватный или удалён после публикации |

## Состояние текущей редакции

- Реализовано только **T1**: `supported_tasks: []`, `self_trained_rl: false`,
  `preferred_speed_mps: null`. T2–T5 не реализованы и потому не заявлены.
- Образ: Ubuntu 22.04.5 LTS + ROS 2 Humble + `rmw_cyclonedds_cpp`, 1.15 ГБ.
- `bash verify.sh` — провалов 0.
- Замер `ping` на Windows/WSL 2: 4.7–5.6 с, из них ~5 с — накладные расходы
  `docker run` (пустой `/bin/true` в том же образе даёт столько же), сам скрипт
  отрабатывает мгновенно.
