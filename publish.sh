#!/usr/bin/env bash
# Публикация образа участника в Registry организаторов и получение digest.
#
#   bash publish.sh <team_name>            # сборка + push + проверка
#   bash publish.sh <team_name> --dry-run  # только показать, что будет сделано
#
# Требует: docker login registry.cookcloud.ru (выполняется вручную, пароль
# в скрипт не передаётся), чистый git status.
set -uo pipefail

TEAM="${1:-}"
DRY="${2:-}"
if [ -z "$TEAM" ]; then
  echo "usage: bash publish.sh <team_name>" >&2
  exit 2
fi

IMAGE="registry.cookcloud.ru/go1-hackathon-remote-stage-${TEAM}/${TEAM}:latest"
REPO="registry.cookcloud.ru/go1-hackathon-remote-stage-${TEAM}/${TEAM}"

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
docker run --rm --network none --entrypoint /entrypoint.sh "$REF" ping > /tmp/go1_ping.txt 2>/dev/null
python3 tools/check_ping.py "$(cygpath -w /tmp/go1_ping.txt 2>/dev/null || echo /tmp/go1_ping.txt)" 0 || \
  echo "ВНИМАНИЕ: проверка ping не прошла" >&2

cat <<EOF

================================================================
Поля для личного кабинета
----------------------------------------------------------------
GitHub (конкретный коммит):
https://github.com/<user>/<repo>/commit/$(git rev-parse HEAD)

Команда загрузки образа:
docker pull --platform linux/amd64 ${REF}
================================================================
EOF
