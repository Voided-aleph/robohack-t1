#!/usr/bin/env bash
# Публикация образа участника в Registry организаторов и получение digest.
#
#   bash publish.sh <team_name>            # сборка + push + проверка
#   bash publish.sh <team_name> --dry-run  # только показать, что будет сделано
#
# Требует: docker login registry.cookcloud.ru (выполняется вручную, пароль
# в скрипт не передаётся), чистый git status.
set -uo pipefail

# MSYS2/Git Bash превращают аргументы вида /entrypoint.sh в виндовые пути —
# docker run тогда падает с "exec: E:/...: no such file or directory".
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'
export MSYS2_ENV_CONV_EXCL='*'

TEAM="${1:-}"
DRY="${2:-}"
if [ -z "$TEAM" ]; then
  echo "usage: bash publish.sh <team_name>" >&2
  exit 2
fi

# Проект в Harbor — go1-hackathon-remote-stage, а имя команды идёт как репозиторий:
#   registry.cookcloud.ru/go1-hackathon-remote-stage/<team>:latest
# (в инструкции орга имя команды дублировалось, но в Harbor дублирования нет).
IMAGE="registry.cookcloud.ru/go1-hackathon-remote-stage/${TEAM}:latest"
REPO="registry.cookcloud.ru/go1-hackathon-remote-stage/${TEAM}"

cd "$(dirname "$0")"

if [ "$DRY" != "--dry-run" ]; then
  if [ -n "$(git status --porcelain)" ]; then
    echo "ОШИБКА: рабочая копия грязная — исходники коммита не совпадут с образом." >&2
    git status --short >&2
    exit 3
  fi
  if ! docker info >/dev/null 2>&1; then
    echo "ОШИБКА: Docker Engine недоступен" >&2
    exit 3
  fi
fi

echo "Образ:   $IMAGE"
echo "Коммит:  $(git rev-parse HEAD)"
echo

if [ "$DRY" = "--dry-run" ]; then
  echo "docker buildx build --platform linux/amd64 --provenance=false --push -t \"$IMAGE\" ."
  exit 0
fi

echo "== Сборка и публикация (linux/amd64) =="
if ! docker buildx build --platform linux/amd64 --provenance=false --push -t "$IMAGE" .; then
  echo "ОШИБКА: сборка/публикация не удалась" >&2
  exit 4
fi

echo
echo "== Манифест в Registry =="
MANIFEST_OUT="$(docker buildx imagetools inspect "$IMAGE")"
printf '%s\n' "$MANIFEST_OUT"
DIGEST="$(printf '%s' "$MANIFEST_OUT" | grep -m1 -oE 'sha256:[a-f0-9]{64}')"

if [ -z "$DIGEST" ]; then
  echo "ОШИБКА: не удалось получить digest из манифеста" >&2
  exit 5
fi
if ! printf '%s' "$MANIFEST_OUT" | grep -qiE 'platform: *linux/amd64'; then
  echo "ОШИБКА: в опубликованном манифесте нет linux/amd64" >&2
  exit 6
fi

REF="${REPO}@${DIGEST}"
echo
echo "== Проверка загрузки по digest =="
docker pull --platform linux/amd64 "$REF" || { echo "ОШИБКА: образ не тянется по digest" >&2; exit 7; }

echo
echo "== ping из скачанного по digest образа (без сети) =="
if docker run --rm --network none --entrypoint /entrypoint.sh "$REF" ping > /tmp/go1_ping.txt 2>/dev/null; then
  PING_OUT="$(cat /tmp/go1_ping.txt)"
  printf '%s\n' "$PING_OUT"
  # Проверка без внешних зависимостей: все четыре поля на месте и exit 0.
  missing=""
  for field in protocol_version supported_tasks self_trained_rl preferred_speed_mps; do
    printf '%s' "$PING_OUT" | grep -q "\"$field\"" || missing="$missing $field"
  done
  if [ -z "$missing" ] && printf '%s' "$PING_OUT" | grep -q '"protocol_version":"1.0"'; then
    echo "  [ OK ] протокол ping корректен"
  else
    echo "ВНИМАНИЕ: в ответе ping не хватает полей:$missing" >&2
  fi
else
  echo "ВНИМАНИЕ: ping из скачанного образа не выполнился" >&2
fi

ORIGIN="$(git remote get-url origin 2>/dev/null | sed -e 's|\.git$||' -e 's|^git@github.com:|https://github.com/|')"
if [ -n "$ORIGIN" ]; then
  COMMIT_URL="${ORIGIN}/commit/$(git rev-parse HEAD)"
else
  COMMIT_URL="https://github.com/<user>/<repo>/commit/$(git rev-parse HEAD)"
fi

cat <<EOF

================================================================
Поля для личного кабинета
----------------------------------------------------------------
GitHub (конкретный коммит):
${COMMIT_URL}

Команда загрузки образа:
docker pull --platform linux/amd64 ${REF}
================================================================
EOF
