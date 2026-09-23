#!/usr/bin/env bash
# scripts/install_dependencies.sh
# Скрипт проверки наличия базовых системных утилит (без установки через sudo)

set -euo pipefail
cd "$(dirname "$0")/.."

echo "=== Проверка базовых системных утилит ==="

for cmd in wget unzip tar; do
    if ! command -v "$cmd" &> /dev/null; then
        echo "ОШИБКА: Утилита $cmd не найдена в PATH."
        echo "Установите её через: apt install $cmd"
        exit 1
    fi
    echo "[OK] $cmd найден"
done

echo "=== Все базовые зависимости проверены ==="
