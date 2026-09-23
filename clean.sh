#!/usr/bin/env bash
# clean.sh
set -euo pipefail
cd "$(dirname "$0")"
source config/project.env

remove_item() {
    if [ "$2" == "dir" ] && [ -d "$1" ]; then rm -rf "$1"; echo "Удален каталог: $1"; fi
    if [ "$2" == "file" ] && [ -f "$1" ]; then rm -f "$1"; echo "Удален файл: $1"; fi
}

echo "Начинаем очистку..."
remove_item "bin" "dir"
remove_item "obj" "dir"
remove_item "build" "dir"
remove_item "results" "dir"
remove_item "tools/dotnet" "dir"
remove_item "tools/bin" "dir"
remove_item "scripts/__pycache__" "dir"
remove_item "harness/bin" "dir"
remove_item "harness/obj" "dir"
echo "Очистка завершена."
