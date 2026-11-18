#!/usr/bin/env python3
"""Строгая проверка ответа `/entrypoint.sh ping` по ТЗ T1 (Hackathon Go1).

Использование:
    python3 check_ping.py <файл-со-stdout> [<код-возврата>]

Проверяет ровно то, что перечислено в п. 3.3 ТЗ:
  * stdout содержит ровно один корректный JSON-объект и ничего кроме него
    (пробельные символы допускаются);
  * protocol_version == "1.0";
  * supported_tasks — массив строк из набора T2..T5 без повторов;
  * self_trained_rl — boolean;
  * preferred_speed_mps — число > 0 либо null;
  * код возврата 0 (если передан).
"""
from __future__ import annotations

import json
import sys

ALLOWED_TASKS = {"T2", "T3", "T4", "T5"}


def fail(msg: str) -> int:
    print(f"FAIL: {msg}")
    return 1


def main(argv: list[str]) -> int:
    if len(argv) < 2:
        print(__doc__)
        return 2

    path = argv[1]
    expected_rc = int(argv[2]) if len(argv) > 2 else None

    with open(path, "rb") as fh:
        raw = fh.read()

    try:
        text = raw.decode("utf-8")
    except UnicodeDecodeError as exc:
        return fail(f"stdout не является валидным UTF-8: {exc}")

    stripped = text.strip()
    if not stripped:
        return fail("stdout пуст")
    if len(stripped.splitlines()) != 1:
        return fail(f"в stdout более одной строки с содержимым ({len(stripped.splitlines())})")

    try:
        obj = json.loads(stripped)
    except json.JSONDecodeError as exc:
        return fail(f"stdout не парсится как JSON: {exc}")

    if not isinstance(obj, dict):
        return fail(f"верхний уровень JSON — {type(obj).__name__}, ожидался объект")

    if obj.get("protocol_version") != "1.0":
        return fail(f'protocol_version == {obj.get("protocol_version")!r}, ожидалось "1.0"')

    tasks = obj.get("supported_tasks")
    if not isinstance(tasks, list) or not all(isinstance(t, str) for t in tasks):
        return fail("supported_tasks должен быть массивом строк")
    bad = [t for t in tasks if t not in ALLOWED_TASKS]
    if bad:
        return fail(f"недопустимые идентификаторы заданий: {bad}")
    if len(set(tasks)) != len(tasks):
        return fail("supported_tasks содержит повторы")

    if not isinstance(obj.get("self_trained_rl"), bool):
        return fail("self_trained_rl должен быть boolean")

    speed = obj.get("preferred_speed_mps", "MISSING")
    if speed == "MISSING":
        return fail("нет поля preferred_speed_mps (нужно число или null)")
    if speed is not None and (isinstance(speed, bool) or not isinstance(speed, (int, float))):
        return fail(f"preferred_speed_mps должен быть числом или null, получено {speed!r}")
    if isinstance(speed, (int, float)) and not speed > 0:
        return fail(f"preferred_speed_mps должен быть > 0, получено {speed}")

    if "T3" not in tasks and speed is not None:
        print("WARN: T3 не заявлено, но preferred_speed_mps != null — по ТЗ ожидается null")
    if expected_rc is not None and expected_rc != 0:
        return fail(f"код возврата {expected_rc}, ожидался 0")

    extra = set(obj) - {"protocol_version", "supported_tasks", "self_trained_rl", "preferred_speed_mps"}
    if extra:
        print(f"WARN: неописанные в ТЗ поля (не запрещены, но и не нужны): {sorted(extra)}")

    print(f"OK: {stripped}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
