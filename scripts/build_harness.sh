#!/usr/bin/env bash
# scripts/build_harness.sh
# Сборка харнесса и создание трёх копий для режимов фаззинга

set -euo pipefail
cd "$(dirname "$0")/.."

source config/project.env

export DOTNET_ROOT="$PROJECT_ROOT/tools/dotnet"
export PATH="$DOTNET_ROOT:$PROJECT_ROOT/tools/bin:$PATH"

echo "=== Сборка харнесса ==="

if [[ ! -f "$PROJECT_ROOT/harness/Harness.csproj" ]]; then
    echo "ОШИБКА: Файл harness/Harness.csproj не найден."
    exit 1
fi

if [[ ! -f "$PROJECT_ROOT/build/Newtonsoft.Json.Bson.dll" ]]; then
    echo "ОШИБКА: Файл build/Newtonsoft.Json.Bson.dll не найден. Сначала выполните ./scripts/build.sh."
    exit 1
fi

if [[ ! -x "$PROJECT_ROOT/tools/bin/sharpfuzz" ]]; then
    echo "ОШИБКА: Инструмент sharpfuzz не найден в tools/bin/. Сначала выполните ./scripts/install_tools.sh."
    exit 1
fi

echo "Шаг 1: Восстановление зависимостей..."
if ! "$DOTNET_ROOT/dotnet" restore "$PROJECT_ROOT/harness/Harness.csproj" --verbosity quiet; then
    echo "ОШИБКА: Не удалось восстановить зависимости для harness/Harness.csproj."
    exit 1
fi
echo "  [OK] Зависимости восстановлены."

# ВАЖНО: собираем во ВРЕМЕННЫЙ каталог, а не сразу в build/.
# Сборка с -o build/ копировала бы из NuGet НЕинструментированную
# Newtonsoft.Json.Bson.dll (без PDB) поверх нашей, и coverlet
# терял бы библиотеку из отчёта покрытия.
echo "Шаг 2: Сборка харнесса (Release) во временный каталог..."
TMP_OUT="$PROJECT_ROOT/build/harness_tmp"
rm -rf "$TMP_OUT"
mkdir -p "$TMP_OUT"
if ! "$DOTNET_ROOT/dotnet" build "$PROJECT_ROOT/harness/Harness.csproj" \
    -c Release \
    -o "$TMP_OUT" \
    --no-restore \
    --verbosity quiet; then
    echo "ОШИБКА: Сборка харнесса завершилась с ошибкой."
    rm -rf "$TMP_OUT"
    exit 1
fi
echo "  [OK] Сборка успешна."

echo "Шаг 3: Копирование файлов харнесса в build/ (библиотеку НЕ трогаем)..."
for f in "$TMP_OUT"/*; do
    base=$(basename "$f")
    # Пропускаем библиотеку и её PDB: в build/ лежит наша
    # инструментированная версия с символами из build.sh
    case "$base" in
        Newtonsoft.Json.Bson.dll|Newtonsoft.Json.Bson.pdb)
            continue
            ;;
    esac
    cp "$f" "$PROJECT_ROOT/build/"
done
rm -rf "$TMP_OUT"
echo "  [OK] Файлы харнесса скопированы, библиотека не перезаписана."

echo "Шаг 4: Контроль инструментирования библиотеки..."
if [[ ! -f "$PROJECT_ROOT/build/.bson_instrumented" ]]; then
    # Маркера нет (например, build/ собран вручную) — инструментируем
    if ! "$PROJECT_ROOT/tools/bin/sharpfuzz" "$PROJECT_ROOT/build/Newtonsoft.Json.Bson.dll"; then
        echo "ОШИБКА: Инструментирование через SharpFuzz завершилось с ошибкой."
        exit 1
    fi
    touch "$PROJECT_ROOT/build/.bson_instrumented"
    echo "  [OK] Библиотека инструментирована."
else
    echo "  [OK] Библиотека уже инструментирована (маркер найден)."
fi

echo "Шаг 5: Создание копий харнесса (С РАСШИРЕНИЕМ .dll)..."
cp "$PROJECT_ROOT/build/Harness.dll" "$PROJECT_ROOT/build/Harness.Reader.dll"
cp "$PROJECT_ROOT/build/Harness.dll" "$PROJECT_ROOT/build/Harness.Writer.dll"
cp "$PROJECT_ROOT/build/Harness.dll" "$PROJECT_ROOT/build/Harness.Differential.dll"
echo "  [OK] Созданы: Harness.Reader.dll, Harness.Writer.dll, Harness.Differential.dll"

echo "Шаг 6: Создание файлов конфигурации и PDB для каждой копии..."
for name in Harness.Reader Harness.Writer Harness.Differential; do
    cp "$PROJECT_ROOT/build/Harness.runtimeconfig.json" "$PROJECT_ROOT/build/${name}.runtimeconfig.json"
    cp "$PROJECT_ROOT/build/Harness.deps.json" "$PROJECT_ROOT/build/${name}.deps.json"
    # PDB-копии убирают SymbolsNotFoundException у coverlet,
    # если он попытается инструментировать копии харнесса
    if [[ -f "$PROJECT_ROOT/build/Harness.pdb" ]]; then
        cp "$PROJECT_ROOT/build/Harness.pdb" "$PROJECT_ROOT/build/${name}.pdb"
    fi
done
echo "  [OK] Файлы .runtimeconfig.json, .deps.json и .pdb созданы."

echo "Шаг 7: Проверка результатов..."
ERRORS=0
for name in Harness.Reader Harness.Writer Harness.Differential; do
    if [[ ! -f "$PROJECT_ROOT/build/${name}.dll" ]]; then
        echo "ОШИБКА: Файл build/${name}.dll не найден."
        ERRORS=1
    fi
    if [[ ! -f "$PROJECT_ROOT/build/${name}.runtimeconfig.json" ]]; then
        echo "ОШИБКА: Файл build/${name}.runtimeconfig.json не найден."
        ERRORS=1
    fi
    if [[ ! -f "$PROJECT_ROOT/build/${name}.deps.json" ]]; then
        echo "ОШИБКА: Файл build/${name}.deps.json не найден."
        ERRORS=1
    fi
done

if [[ "$ERRORS" -ne 0 ]]; then
    echo "ОШИБКА: Не все файлы харнесса были созданы."
    exit 1
fi
echo "  [OK] Все файлы на месте."

echo ""
echo "=== Сборка харнесса завершена ==="
ls -lh "$PROJECT_ROOT/build/"Harness* 2>/dev/null || true
