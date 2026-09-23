#!/usr/bin/env bash
# scripts/install_tools.sh
# Скрипт локальной установки .NET SDK и инструментов фаззинга (идемпотентный)

set -euo pipefail
cd "$(dirname "$0")/.."

# Загружаем переменные окружения
source config/project.env

echo "=== Установка инструментов ==="

# Настройка переменных для локальной установки .NET
export DOTNET_ROOT="$PROJECT_ROOT/tools/dotnet"
export PATH="$DOTNET_ROOT:$PROJECT_ROOT/tools/bin:$PATH"

# 1. Установка .NET SDK 8.0.425
DOTNET_URL="https://builds.dotnet.microsoft.com/dotnet/Sdk/8.0.425/dotnet-sdk-8.0.425-linux-x64.tar.gz"
DOTNET_ARCHIVE="dotnet-sdk.tar.gz"
SKIP_DOTNET_INSTALL=0

# Идемпотентность: проверяем наличие уже установленного SDK нужной версии
if [[ -x "$DOTNET_ROOT/dotnet" ]]; then
    EXISTING_VERSION=$("$DOTNET_ROOT/dotnet" --version 2>/dev/null | tr -d '\r\n')
    if [[ "$EXISTING_VERSION" == "8.0.425" ]]; then
        echo "[OK] .NET SDK уже установлен: 8.0.425"
        SKIP_DOTNET_INSTALL=1
    fi
fi

if [[ "$SKIP_DOTNET_INSTALL" -ne 1 ]]; then
    echo "Скачивание .NET SDK 8.0.425..."
    if ! wget -q -O "$DOTNET_ARCHIVE" "$DOTNET_URL"; then
        echo "ОШИБКА: Не удалось скачать .NET SDK. Проверьте подключение к интернету или корректность URL."
        rm -f "$DOTNET_ARCHIVE"
        exit 1
    fi

    echo "Распаковка .NET SDK в $DOTNET_ROOT..."
    mkdir -p "$DOTNET_ROOT"
    if ! tar -zxf "$DOTNET_ARCHIVE" -C "$DOTNET_ROOT"; then
        echo "ОШИБКА: Не удалось распаковать архив .NET SDK."
        rm -f "$DOTNET_ARCHIVE"
        exit 1
    fi
    rm -f "$DOTNET_ARCHIVE"

    # Проверка установки dotnet
    DOTNET_VERSION=$("$DOTNET_ROOT/dotnet" --version | tr -d '\r\n')
    if [[ "$DOTNET_VERSION" != "8.0.425" ]]; then
        echo "ОШИБКА: Ожидалась версия .NET SDK 8.0.425, но получена: $DOTNET_VERSION"
        exit 1
    fi
    echo "[OK] .NET SDK установлен: $DOTNET_VERSION"
fi

# 2. Установка dotnet-инструментов в tools/bin/
mkdir -p "$PROJECT_ROOT/tools/bin"

# Функция для установки и проверки инструмента (идемпотентная)
install_and_check_tool() {
    local tool_name="$1"
    local tool_version="${2:-}"
    local bin_name=""
    local install_args=()

    # Определяем имя бинарного файла
    case "$tool_name" in
        "SharpFuzz.CommandLine")
            bin_name="sharpfuzz"
            ;;
        "coverlet.console")
            bin_name="coverlet"
            ;;
        "dotnet-reportgenerator-globaltool")
            bin_name="reportgenerator"
            ;;
    esac

    # Идемпотентность: проверяем наличие уже установленного инструмента
    if [[ -x "$PROJECT_ROOT/tools/bin/$bin_name" ]]; then
        echo "[OK] $tool_name уже установлен"
        return 0
    fi

    # Фиксируем версию, если она задана (критично для SharpFuzz)
    if [[ -n "$tool_version" ]]; then
        install_args+=(--version "$tool_version")
    fi

    echo "Установка $tool_name ${tool_version:+(версия $tool_version)}..."
    if ! "$DOTNET_ROOT/dotnet" tool install --tool-path "$PROJECT_ROOT/tools/bin" "${install_args[@]}" "$tool_name" &> /dev/null; then
        echo "ОШИБКА: Не удалось установить $tool_name."
        if [[ "$tool_name" == "SharpFuzz.CommandLine" ]]; then
            echo "Поиск похожих пакетов:"
            "$DOTNET_ROOT/dotnet" tool search SharpFuzz
        fi
        exit 1
    fi

    # Проверка успешной установки: бинарник должен существовать и быть исполняемым
    if [[ ! -x "$PROJECT_ROOT/tools/bin/$bin_name" ]]; then
        echo "ОШИБКА: Бинарный файл $bin_name не найден после установки."
        exit 1
    fi

    # Индивидуальная проверка версии для каждого инструмента
    case "$bin_name" in
        "coverlet")
            if ! "$PROJECT_ROOT/tools/bin/coverlet" --version &> /dev/null; then
                echo "ОШИБКА: Не удалось проверить версию $tool_name."
                exit 1
            fi
            ;;
        "sharpfuzz"|"reportgenerator")
            ;;
    esac

    echo "[OK] $tool_name установлен и проверен"
}

# ВАЖНО: SharpFuzz.CommandLine устанавливается с фиксированной версией 2.3.0,
# чтобы совпадать с runtime-библиотекой SharpFuzz в harness/Harness.csproj.
# Несовпадение версий вызывает AccessViolationException при работе shared memory AFL++.
install_and_check_tool "SharpFuzz.CommandLine" "2.3.0"
install_and_check_tool "coverlet.console"
install_and_check_tool "dotnet-reportgenerator-globaltool"

echo "=== Установка инструментов завершена ==="
