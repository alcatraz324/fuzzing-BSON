#!/usr/bin/env bash
# run_all.sh
# Главный диспетчер: последовательный запуск всех этапов фаззинга
# и открытие результатов (логи крашей + HTML-отчёт покрытия) в конце.

set -euo pipefail
cd "$(dirname "$0")"

# Загружаем конфигурацию
source config/project.env

# Генерируем уникальный идентификатор запуска
RUN_ID=$(date -u +"%Y%m%dT%H%M%SZ")-$$
export RUN_ID

echo "Запуск фаззинга. RUN_ID: $RUN_ID"

# Создаём структуру директорий для результатов
mkdir -p "results/${RUN_ID}/reader"
mkdir -p "results/${RUN_ID}/writer"
mkdir -p "results/${RUN_ID}/differential"
mkdir -p "results/${RUN_ID}/crash_analysis_report"

# Сохраняем ID последнего запуска
echo "$RUN_ID" > results/latest.txt

# Функция для безопасного вызова скриптов
run_script() {
    local script_path="$1"
    if [ -x "$script_path" ]; then
        echo ">>> Выполнение: $script_path"
        "$script_path" || true
    else
        echo "!!! ПРЕДУПРЕЖДЕНИЕ: Скрипт $script_path не найден или не является исполняемым. Пропускаем."
    fi
}

# Последовательный вызов всех этапов
run_script "./scripts/check_environment.sh"
run_script "./scripts/install_dependencies.sh"
run_script "./scripts/install_tools.sh"
run_script "./scripts/build.sh"
run_script "./scripts/build_harness.sh"
run_script "./scripts/create_corpus.sh"
run_script "./scripts/create_dictionary.sh"
run_script "./scripts/fuzz.sh"
run_script "./scripts/analyze_crashes.sh"
# сбор ВСЕХ крашей, воспроизведение, единый лог + сигнатуры
run_script "./scripts/repro_all_crashes.sh"
run_script "./scripts/coverage.sh"
run_script "./scripts/report.sh"

# ПОСЛЕ ФАЗЗИНГА И ВСЕХ ОТЧЁТОВ: открытие необходимых логов и HTML-отчёта
echo ">>> Открытие результатов: логи крашей и HTML-отчёт покрытия"
if [ -x "./open_results.sh" ]; then
    ./open_results.sh || true
else
    echo "!!! ПРЕДУПРЕЖДЕНИЕ: open_results.sh не найден или не исполняемый."
fi

echo "=== ВСЕ ЭТАПЫ ЗАВЕРШЕНЫ ==="
echo "Результаты сохранены в: results/${RUN_ID}/"
