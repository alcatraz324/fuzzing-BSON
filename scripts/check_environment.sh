#!/usr/bin/env bash
# scripts/check_environment.sh
# Скрипт проверки системного окружения и наличия необходимых компонентов

set -euo pipefail
cd "$(dirname "$0")/.."

# Загружаем переменные окружения
source config/project.env

echo "=== Проверка окружения ==="

# 1. Проверка ОС (Linux x86_64)
OS_NAME=$(uname -s)
OS_ARCH=$(uname -m)
if [[ "$OS_NAME" != "Linux" || "$OS_ARCH" != "x86_64" ]]; then
    echo "ОШИБКА: Требуется Linux x86_64. Обнаружено: $OS_NAME $OS_ARCH"
    exit 1
fi
echo "[OK] ОС: $OS_NAME $OS_ARCH"

# 2. Проверка Python 3.11+
if ! command -v python3 &> /dev/null; then
    echo "ОШИБКА: Python 3 не найден в PATH."
    exit 1
fi
PYTHON_VERSION=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')
PYTHON_MAJOR=$(echo "$PYTHON_VERSION" | cut -d. -f1)
PYTHON_MINOR=$(echo "$PYTHON_VERSION" | cut -d. -f2)
if [[ "$PYTHON_MAJOR" -lt 3 || ("$PYTHON_MAJOR" -eq 3 && "$PYTHON_MINOR" -lt 11) ]]; then
    echo "ОШИБКА: Требуется Python 3.11+. Обнаружено: $PYTHON_VERSION"
    exit 1
fi
echo "[OK] Python: $PYTHON_VERSION"

# 3. Проверка git
if ! command -v git &> /dev/null; then
    echo "ОШИБКА: git не найден в PATH."
    exit 1
fi
echo "[OK] git: $(git --version)"

# 4. Проверка AFL++ 5.02c
if ! command -v afl-fuzz &> /dev/null; then
    echo "ОШИБКА: afl-fuzz не найден в PATH."
    exit 1
fi
AFL_VERSION=$(afl-fuzz --version 2>&1 | grep -oE '[0-9]+\.[0-9]+[a-z]+' | head -n 1)
if [[ "$AFL_VERSION" != "5.02c" ]]; then
    echo "ОШИБКА: Требуется AFL++ версии 5.02c. Обнаружено: $AFL_VERSION"
    exit 1
fi
echo "[OK] AFL++: $AFL_VERSION"

# 5. Проверка дискового пространства (минимум 2 ГБ)
AVAILABLE_GB=$(df -BG "$PROJECT_ROOT" | awk 'NR==2 {print $4}' | sed 's/G//')
if [[ "$AVAILABLE_GB" -lt 2 ]]; then
    echo "ОШИБКА: Недостаточно дискового пространства. Требуется минимум 2 ГБ, доступно: ${AVAILABLE_GB} ГБ."
    exit 1
fi
echo "[OK] Дисковое пространство: ${AVAILABLE_GB} ГБ"

# 6. Проверка каталога source/ и репозитория
if [[ ! -d "$PROJECT_ROOT/source/Newtonsoft.Json.Bson" ]]; then
    echo "ОШИБКА: Каталог source/Newtonsoft.Json.Bson не найден. Клонируйте репозиторий."
    exit 1
fi
echo "[OK] Исходный код Newtonsoft.Json.Bson найден"

echo "=== Проверка окружения завершена успешно ==="
