#!/usr/bin/env bash
# scripts/build.sh
# Сборка целевой библиотеки, pristine-копии для coverage и инструментирование
# через SharpFuzz. Идемпотентный блок: при отсутствии source/ исходники
# клонируются автоматически (тег 1.0.3).

set -euo pipefail
cd "$(dirname "$0")/.."

source config/project.env

export DOTNET_ROOT="$PROJECT_ROOT/tools/dotnet"
export PATH="$DOTNET_ROOT:$PROJECT_ROOT/tools/bin:$PATH"

# ------------------------------------------------------------
# Идемпотентный блок: исходный код целевой библиотеки
# - source/Newtonsoft.Json.Bson есть и содержит csproj -> ничего не делаем
# - отсутствует или повреждён -> клонируем тег 1.0.3 с GitHub
# - нет сети/git -> понятная ошибка с инструкцией по ручному клонированию
# ------------------------------------------------------------
SOURCE_DIR="$PROJECT_ROOT/source/Newtonsoft.Json.Bson"
SOURCE_URL="https://github.com/JamesNK/Newtonsoft.Json.Bson"
SOURCE_TAG="1.0.3"

echo "=== Сборка проекта ==="
echo "Шаг 0: Проверка исходного кода целевой библиотеки..."

if [[ -d "$SOURCE_DIR" ]] && \
   [[ -n "$(find "$SOURCE_DIR" -name 'Newtonsoft.Json.Bson.csproj' -type f 2>/dev/null | head -n 1)" ]]; then
    echo "  [OK] Исходный код уже присутствует: $SOURCE_DIR (клонирование пропущено)"
else
    if ! command -v git &> /dev/null; then
        echo "ОШИБКА: git не найден. Установите git или клонируйте репозиторий вручную:"
        echo "  git clone --branch $SOURCE_TAG $SOURCE_URL $SOURCE_DIR"
        exit 1
    fi

    if [[ -d "$SOURCE_DIR" ]]; then
        echo "  ПРЕДУПРЕЖДЕНИЕ: $SOURCE_DIR существует, но csproj не найден - клон повреждён."
        echo "  Удаляю и клонирую заново."
        rm -rf "$SOURCE_DIR"
    fi

    echo "  [INFO] Клонирую $SOURCE_URL (тег $SOURCE_TAG)..."
    mkdir -p "$PROJECT_ROOT/source"
    if ! git clone --branch "$SOURCE_TAG" --depth 1 "$SOURCE_URL" "$SOURCE_DIR"; then
        echo "ОШИБКА: Не удалось клонировать репозиторий."
        echo "  Возможные причины: нет доступа к сети или репозиторий недоступен."
        echo "  Клонируйте вручную: git clone --branch $SOURCE_TAG $SOURCE_URL $SOURCE_DIR"
        exit 1
    fi

    CLONED_TAG=$(git -C "$SOURCE_DIR" describe --tags 2>/dev/null || echo "")
    if [[ "$CLONED_TAG" == "$SOURCE_TAG" ]]; then
        echo "  [OK] Репозиторий клонирован, тег проверен: $CLONED_TAG"
    else
        echo "  ПРЕДУПРЕЖДЕНИЕ: ожидался тег $SOURCE_TAG, получен: '${CLONED_TAG:-не определён}'"
    fi
fi

if [[ ! -x "$PROJECT_ROOT/tools/bin/sharpfuzz" ]]; then
    echo "ОШИБКА: Инструмент sharpfuzz не найден в tools/bin/. Сначала выполните ./scripts/install_tools.sh."
    exit 1
fi

CSPROJ_FILE=$(find "$SOURCE_DIR" -name "Newtonsoft.Json.Bson.csproj" -type f | head -n 1)
if [[ -z "$CSPROJ_FILE" ]]; then
    echo "ОШИБКА: Файл Newtonsoft.Json.Bson.csproj не найден в $SOURCE_DIR"
    exit 1
fi
echo "[OK] Найден проект: $CSPROJ_FILE"

echo "Шаг 1: Восстановление зависимостей (dotnet restore)..."
if ! "$DOTNET_ROOT/dotnet" restore "$CSPROJ_FILE" --verbosity quiet; then
    echo "ОШИБКА: Не удалось восстановить зависимости для Newtonsoft.Json.Bson."
    exit 1
fi
echo "  [OK] Зависимости восстановлены."

echo "Шаг 2: Сборка source/Newtonsoft.Json.Bson (Release)..."
mkdir -p "$PROJECT_ROOT/build/intermediate"
if ! "$DOTNET_ROOT/dotnet" build "$CSPROJ_FILE" \
    -c Release \
    -o "$PROJECT_ROOT/build/intermediate" \
    --no-restore \
    --verbosity quiet; then
    echo "ОШИБКА: Сборка Newtonsoft.Json.Bson завершилась с ошибкой."
    exit 1
fi
echo "  [OK] Сборка успешна."

echo "Шаг 3: Сохранение pristine-копии для coverage..."
mkdir -p "$PROJECT_ROOT/build/pristine"
cp "$PROJECT_ROOT/build/intermediate/Newtonsoft.Json.Bson.dll" "$PROJECT_ROOT/build/pristine/"
if [[ -f "$PROJECT_ROOT/build/intermediate/Newtonsoft.Json.Bson.pdb" ]]; then
    cp "$PROJECT_ROOT/build/intermediate/Newtonsoft.Json.Bson.pdb" "$PROJECT_ROOT/build/pristine/"
    echo "  [OK] Pristine-копия с PDB сохранена в build/pristine/."
else
    echo "  ПРЕДУПРЕЖДЕНИЕ: PDB не найден - coverage может не собраться."
fi

echo "Шаг 4: Инструментирование Newtonsoft.Json.Bson.dll через SharpFuzz..."
if ! "$PROJECT_ROOT/tools/bin/sharpfuzz" "$PROJECT_ROOT/build/intermediate/Newtonsoft.Json.Bson.dll"; then
    echo "ОШИБКА: Инструментирование через SharpFuzz завершилось с ошибкой."
    exit 1
fi
echo "  [OK] Инструментирование завершено."

echo "Шаг 5: Копирование инструментированной DLL и PDB в build/..."
cp "$PROJECT_ROOT/build/intermediate/Newtonsoft.Json.Bson.dll" "$PROJECT_ROOT/build/"
if [[ -f "$PROJECT_ROOT/build/intermediate/Newtonsoft.Json.Bson.pdb" ]]; then
    cp "$PROJECT_ROOT/build/intermediate/Newtonsoft.Json.Bson.pdb" "$PROJECT_ROOT/build/"
fi
touch "$PROJECT_ROOT/build/.bson_instrumented"
echo "  [OK] Инструментированная DLL скопирована в build/."

echo "Шаг 6: Копирование зависимостей..."
if [[ -f "$PROJECT_ROOT/build/intermediate/Newtonsoft.Json.dll" ]]; then
    cp "$PROJECT_ROOT/build/intermediate/Newtonsoft.Json.dll" "$PROJECT_ROOT/build/"
    echo "  [OK] Newtonsoft.Json.dll скопирована."
else
    echo "  [INFO] Newtonsoft.Json.dll не найдена в промежуточной сборке."
fi

echo ""
echo "=== Сборка завершена успешно ==="
echo "Файлы в build/:"
ls -lh "$PROJECT_ROOT/build/" 2>/dev/null | grep -v "^total" | grep -v "^d" || echo "  (пусто)"
