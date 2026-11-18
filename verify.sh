#!/usr/bin/env bash
# Локальная имитация проверки T1 организаторами.
# Запускать на машине с Docker (Linux / macOS / Windows+Docker Desktop, git-bash).
#
#   bash verify.sh                          # собрать go1-participant:verify и проверить
#   IMAGE=... IMAGE_READY=1 bash verify.sh  # проверить уже собранный локальный образ
set -uo pipefail

# MSYS2 (UCRT64/MINGW64) и Git Bash «переводят» аргументы, начинающиеся с '/',
# в виндовые пути: --entrypoint /entrypoint.sh превращается в E:/Git/entrypoint.sh,
# и docker падает с "exec: E:/...: no such file or directory". Отключаем это.
export MSYS_NO_PATHCONV=1
export MSYS2_ARG_CONV_EXCL='*'
export MSYS2_ENV_CONV_EXCL='*'
# Без подсказок Docker CLI («What's next: … Gordon») в выводе проверок.
export DOCKER_CLI_HINTS=false

cd "$(dirname "$0")"
IMAGE="${IMAGE:-go1-participant:verify}"
PY="${PYTHON:-python3}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
fails=0
ok()   { printf '  [ OK ]   %s\n' "$*"; }
bad()  { printf '  [ FAIL ] %s\n' "$*"; fails=$((fails+1)); }
info() { printf '  [info]   %s\n' "$*"; }

# Нативный Python на Windows/MSYS не понимает пути вида /tmp/... — конвертируем.
win_path() {
  if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else printf '%s' "$1"; fi
}

echo "== 0/6 Предполётные проверки файлов =="
if grep -qU $'\r' entrypoint.sh 2>/dev/null; then
  bad "entrypoint.sh содержит CRLF — в контейнере получите '\\r: not found'"
else
  ok "entrypoint.sh с LF-переводами строк"
fi
if [ -f .gitattributes ] && grep -q 'eol=lf' .gitattributes; then
  ok ".gitattributes закрепляет LF"
else
  bad "нет .gitattributes с eol=lf"
fi

if [ -z "${IMAGE_READY:-}" ]; then
  echo "== 1/6 Сборка linux/amd64 =="
  if docker buildx build --platform linux/amd64 --load -t "$IMAGE" . >"$TMP/build.log" 2>&1; then
    ok "образ собран: $IMAGE"
  else
    bad "сборка не удалась"
    tail -20 "$TMP/build.log"
    echo; echo "ИТОГ: сборка провалена"; exit 1
  fi
fi

echo "== 2/6 Архитектура и ОС образа =="
arch="$(docker image inspect --format '{{.Os}}/{{.Architecture}}' "$IMAGE")"
if [ "$arch" = "linux/amd64" ]; then ok "platform = $arch"; else bad "platform = $arch, требуется linux/amd64"; fi
base="$(docker run --rm --network none --entrypoint /bin/sh "$IMAGE" -c 'grep PRETTY_NAME /etc/os-release' 2>/dev/null)"
case "$base" in
  *22.04*) ok "база: $base";;
  "")      info "не удалось прочитать /etc/os-release";;
  *)       info "база: $base (ТЗ требует Ubuntu 22.04)";;
esac

echo "== 3/6 Контракт: /entrypoint.sh исполняем, не root, без CRLF =="
if docker run --rm --network none --entrypoint /bin/sh "$IMAGE" -c 'test -x /entrypoint.sh'; then
  ok "/entrypoint.sh исполняем"
else
  bad "/entrypoint.sh отсутствует или не исполняем"
fi
uid="$(docker run --rm --network none --entrypoint /bin/sh "$IMAGE" -c 'id -u' 2>/dev/null)"
if [ -n "$uid" ] && [ "$uid" != "0" ]; then
  ok "запуск от uid=$uid (не root)"
elif [ "$uid" = "0" ]; then
  bad "контейнер работает от root"
else
  bad "не удалось определить uid (контейнер не запустился)"
fi
CR=$(printf '\r')
# Вердикт считается внутри контейнера и всегда завершается кодом 0: иначе Docker
# CLI считает ожидаемый код 1 «ошибкой» и печатает свою подсказку в stderr.
crlf="$(docker run --rm --network none --entrypoint /bin/sh "$IMAGE" \
  -c "if grep -q '$CR' /entrypoint.sh; then echo CRLF; else echo LF; fi" 2>/dev/null)"
case "$crlf" in
  LF)   ok "в образе /entrypoint.sh без CRLF";;
  CRLF) bad "в образе /entrypoint.sh содержит CRLF";;
  *)    bad "не удалось проверить /entrypoint.sh (контейнер не запустился)";;
esac

echo "== 4/6 ping: код возврата, JSON, время (сеть отключена) =="
start=$(date +%s%N)
docker run --rm --network none --entrypoint /entrypoint.sh "$IMAGE" ping \
  >"$TMP/out.txt" 2>"$TMP/err.txt"
rc=$?
elapsed_ms=$(( ( $(date +%s%N) - start ) / 1000000 ))

if "$PY" tools/check_ping.py "$(win_path "$TMP/out.txt")" "$rc"; then
  ok "протокол ping корректен"
else
  bad "протокол ping нарушен"
fi
if [ "$elapsed_ms" -lt 10000 ]; then
  ok "время выполнения ${elapsed_ms} мс (< 10000)"
else
  bad "время выполнения ${elapsed_ms} мс — превышает 10 с"
fi
if [ -s "$TMP/err.txt" ]; then info "stderr (допустимо): $(tr '\n' ' ' <"$TMP/err.txt")"; fi

echo "== 5/6 Повтор ping x5: стабильность ответа =="
prev=""; stable=1
for _ in 1 2 3 4 5; do
  cur="$(docker run --rm --network none --entrypoint /entrypoint.sh "$IMAGE" ping 2>/dev/null)"
  [ -n "$cur" ] || stable=0
  [ -z "$prev" ] && prev="$cur"
  [ "$cur" = "$prev" ] || stable=0
done
if [ "$stable" = 1 ]; then ok "ответ стабилен"; else bad "ответы различаются между запусками (или пустые)"; fi

echo "== 6/6 Незаявленные задания завершаются с ошибкой в stderr =="
declared="$(cat "$TMP/out.txt")"
for task in T2 T3 T4 T5; do
  case "$declared" in
    *"\"$task\""*) info "$task заявлен в supported_tasks — запуск проверяется вручную"; continue;;
  esac
  docker run --rm --network none --entrypoint /entrypoint.sh "$IMAGE" "$task" >"$TMP/o" 2>"$TMP/e"
  code=$?
  if grep -q 'docker: Error' "$TMP/e" 2>/dev/null || [ "$code" -ge 125 ]; then
    bad "$task -> ошибка запуска контейнера (код $code), а не отказ решения"
    head -3 "$TMP/e" | sed 's/^/           /'
  elif [ "$code" -ne 0 ] && [ ! -s "$TMP/o" ] && [ -s "$TMP/e" ]; then
    ok "$task -> код $code, stdout пуст, диагностика в stderr"
  else
    bad "$task -> код $code; ожидался ненулевой код при пустом stdout"
  fi
done

echo
if [ "$fails" -eq 0 ]; then
  echo "ИТОГ: все проверки пройдены."
  exit 0
else
  echo "ИТОГ: провалено проверок: $fails"
  exit 1
fi
