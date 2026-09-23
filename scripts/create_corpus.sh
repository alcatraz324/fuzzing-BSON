#!/usr/bin/env bash
# scripts/create_corpus.sh
# Генерация начального seed-корпуса валидных BSON-документов

set -euo pipefail
cd "$(dirname "$0")/.."

# Загружаем переменные окружения
source config/project.env

echo "=== Генерация seed-корпуса ==="

# Создаём каталоги для каждого режима фаззинга
mkdir -p "$PROJECT_ROOT/build/corpus/reader"
mkdir -p "$PROJECT_ROOT/build/corpus/writer"
mkdir -p "$PROJECT_ROOT/build/corpus/differential"

# Запуск генератора корпуса
python3 "$PROJECT_ROOT/scripts/generate_corpus.py" \
    --output-dir "$PROJECT_ROOT/build/corpus"

# Подсчёт файлов в каждом каталоге
echo ""
echo "=== Подсчёт файлов корпуса ==="
for mode in reader writer differential; do
    count=$(find "$PROJECT_ROOT/build/corpus/$mode" -type f | wc -l)
    echo "  $mode: $count файлов"
done

echo ""
echo "=== Генерация корпуса завершена ==="
