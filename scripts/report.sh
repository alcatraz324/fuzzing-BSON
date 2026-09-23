#!/usr/bin/env bash
# scripts/report.sh
# Обёртка для запуска генерации сводного отчёта

set -euo pipefail
cd "$(dirname "$0")/.."

# Загружаем переменные окружения
source config/project.env

echo "=== Генерация сводного отчёта ==="

# Формируем аргументы для Python-скрипта
ARGS=(--project-root "$PROJECT_ROOT")

# Если RUN_ID задан в окружении (от run_all.sh), передаём его
if [[ -n "${RUN_ID:-}" ]]; then
    ARGS+=(--run-id "$RUN_ID")
fi

python3 "$PROJECT_ROOT/scripts/generate_report.py" "${ARGS[@]}"

echo ""
echo "=== Генерация сводного отчёта завершена ==="
