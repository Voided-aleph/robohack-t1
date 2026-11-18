#!/usr/bin/env bash
# /entrypoint.sh — контракт запуска решения (задание T1, Hackathon Go1).
#
# Соглашение:  /entrypoint.sh ping    -> ровно один JSON в stdout, exit 0, < 10 c
#              /entrypoint.sh T2..T5  -> запуск решения команды до остановки контейнера
#
# ВАЖНО: этот файл должен иметь LF-переводы строк (не CRLF) и быть
# исполняемым внутри образа (/entrypoint.sh, chmod 0755).
set -euo pipefail

# ---------------------------------------------------------------------------
# Значения протокола. Правьте ТОЛЬКО здесь.
# ---------------------------------------------------------------------------
PROTOCOL_VERSION="1.0"

# Перечень РЕАЛЬНО реализованных заданий, строго латинскими T.
# Если сделано только T1 — пустой массив.
SUPPORTED_TASKS_JSON='[]'
# примеры: '["T2"]'   '["T2","T3"]'   '["T2","T3","T4","T5"]'

# true только если RL-политика обучена/дообучена командой самостоятельно.
SELF_TRAINED_RL="false"

# Рекомендуемая скорость ходьбы для T3 в м/с, либо null если T3 не реализовано.
PREFERRED_SPEED_MPS="null"

# ---------------------------------------------------------------------------
# Служебные сообщения — только в stderr: stdout при ping обязан быть чистым.
# ---------------------------------------------------------------------------
err() { printf '%s\n' "$*" >&2; }

usage() {
    err "usage: /entrypoint.sh {ping|T2|T3|T4|T5}"
    err "  ping  — сведения о решении в формате JSON (протокол 1.0)"
    err "  T2..T5 — запуск реализованного задания"
}

cmd="${1:-}"

case "$cmd" in
    ping)
        # Единственный объект в stdout; перевод строки — допустимый пробельный символ.
        printf '{"protocol_version":"%s","supported_tasks":%s,"self_trained_rl":%s,"preferred_speed_mps":%s}\n' \
            "$PROTOCOL_VERSION" "$SUPPORTED_TASKS_JSON" "$SELF_TRAINED_RL" "$PREFERRED_SPEED_MPS"
        exit 0
        ;;

    T2|T3|T4|T5)
        # В образе есть ROS 2 Humble — подключаем окружение перед запуском узла.
        # setup.bash несовместим с `set -u` (падает на AMENT_TRACE_SETUP_FILES),
        # поэтому nounset на время source отключаем. stdout гасим: он должен
        # оставаться чистым.
        if [ ! -f /opt/ros/humble/setup.bash ]; then
            err "ROS 2 Humble environment is not available in this image"
            exit 70
        fi
        set +u
        # shellcheck disable=SC1091
        source /opt/ros/humble/setup.bash >/dev/null 2>&1
        set -u

        # Здесь должен запускаться узел задания. Пока задание не реализовано —
        # честный отказ, код возврата != 0, диагностика в stderr.
        # Реализованное задание вместо exit должно делать:
        #   exec ros2 run <пакет> <узел>
        err "task $cmd is not implemented in this image (ROS 2 Humble ready, RMW=${RMW_IMPLEMENTATION:-default})"
        exit 64
        ;;

    "")
        err "error: no command given"
        usage
        exit 64
        ;;

    *)
        err "error: unknown command '$cmd'"
        usage
        exit 64
        ;;
esac
