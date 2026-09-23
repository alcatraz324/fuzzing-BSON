#!/usr/bin/env bash
# scripts/coverage.sh
# Сбор покрытия БИБЛИОТЕКИ через coverlet в изолированном cov_app
# (pristine-копия без SharpFuzz-инструментации) + HTML через reportgenerator.
# Позиционный аргумент coverlet — КАТАЛОГ cov_app, без include/exclude-фильтров.
# Фокусировка отчёта на библиотеке — через -classfilters reportgenerator.

set -euo pipefail
cd "$(dirname "$0")/.."

source config/project.env

export DOTNET_ROOT="$PROJECT_ROOT/tools/dotnet"
export PATH="$DOTNET_ROOT:$PROJECT_ROOT/tools/bin:$PATH"

echo "=== Сбор метрик покрытия кода ==="

for tool in coverlet reportgenerator; do
    if [[ ! -x "$PROJECT_ROOT/tools/bin/$tool" ]]; then
        echo "ОШИБКА: $tool не найден в tools/bin/. Сначала выполните ./scripts/install_tools.sh."
        exit 1
    fi
done
echo "[OK] coverlet и reportgenerator найдены."

if [[ ! -f "$PROJECT_ROOT/build/pristine/Newtonsoft.Json.Bson.dll" ]]; then
    echo "ОШИБКА: build/pristine/Newtonsoft.Json.Bson.dll не найдена."
    echo "  Запустите ./scripts/build.sh — он создаёт pristine-копию до SharpFuzz."
    exit 1
fi
if [[ ! -f "$PROJECT_ROOT/build/pristine/Newtonsoft.Json.Bson.pdb" ]]; then
    echo "ОШИБКА: build/pristine/Newtonsoft.Json.Bson.pdb не найдена."
    echo "  Без PDB coverlet не сможет инструментировать библиотеку."
    exit 1
fi
echo "[OK] Pristine-копия библиотеки с PDB найдена."

for mode in reader writer differential; do
    if [[ ! -f "$PROJECT_ROOT/build/Harness.${mode^}.dll" ]]; then
        echo "ОШИБКА: Харнесс не найден: build/Harness.${mode^}.dll"
        exit 1
    fi
done
echo "[OK] Все харнессы найдены."

if [[ -z "${RUN_ID:-}" ]]; then
    if [[ -f "$PROJECT_ROOT/results/latest.txt" ]]; then
        RUN_ID=$(cat "$PROJECT_ROOT/results/latest.txt")
    else
        RUN_ID=$(date -u +"%Y%m%dT%H%M%SZ")-$$
        mkdir -p "$PROJECT_ROOT/results"
        echo "$RUN_ID" > "$PROJECT_ROOT/results/latest.txt"
    fi
fi
export RUN_ID

COVERAGE_DIR="$PROJECT_ROOT/results/$RUN_ID/coverage"
mkdir -p "$COVERAGE_DIR"

# ------------------------------------------------------------
# Изолированное coverage-приложение: все зависимости из build/
# (включая SharpFuzz.dll, SharpFuzz.Common.dll, dnlib.dll),
# поверх которых кладётся pristine-библиотека с PDB.
# ------------------------------------------------------------
COV_APP="$PROJECT_ROOT/build/cov_app"
echo ""
echo "=== Подготовка изолированного coverage-приложения: $COV_APP ==="
rm -rf "$COV_APP"
mkdir -p "$COV_APP"

for f in "$PROJECT_ROOT/build/"*.dll "$PROJECT_ROOT/build/"*.pdb "$PROJECT_ROOT/build/"*.json; do
    [[ -e "$f" ]] && cp "$f" "$COV_APP/"
done
cp "$PROJECT_ROOT/build/pristine/Newtonsoft.Json.Bson.dll" "$COV_APP/"
cp "$PROJECT_ROOT/build/pristine/Newtonsoft.Json.Bson.pdb" "$COV_APP/"

for req in SharpFuzz.dll SharpFuzz.Common.dll Newtonsoft.Json.dll \
           Newtonsoft.Json.Bson.pdb Harness.Reader.dll Harness.Writer.dll \
           Harness.Differential.dll; do
    if [[ ! -f "$COV_APP/$req" ]]; then
        echo "ОШИБКА: В cov_app отсутствует обязательный файл: $req"
        exit 1
    fi
done
echo "[OK] Coverage-приложение готово ($(find "$COV_APP" -maxdepth 1 -type f | wc -l) файлов)."

# Smoke-тест: один запуск харнесса до массовых прогонов
SMOKE_LOG="$COVERAGE_DIR/cov_app_smoke.log"
first_seed=$(find "$PROJECT_ROOT/build/corpus/reader" -type f 2>/dev/null | sort | head -n 1)
if [[ -z "$first_seed" ]]; then
    echo "ОШИБКА: Нет сидов в build/corpus/reader. Запустите ./scripts/create_corpus.sh."
    exit 1
fi
if ! (cd "$COV_APP" && "$DOTNET_ROOT/dotnet" "$COV_APP/Harness.Reader.dll" "$first_seed" >"$SMOKE_LOG" 2>&1); then
    echo "ОШИБКА: Smoke-тест cov_app завершился с ошибкой — зависимости неполные:"
    tail -n 5 "$SMOKE_LOG"
    exit 1
fi
echo "[OK] Smoke-тест cov_app пройден."

COLLECTED_XML=()

# ------------------------------------------------------------
# Прогон coverlet по всем сидам режима (вывод — в лог режима)
#   $1 — режим
# ------------------------------------------------------------
run_coverlet_mode() {
    local mode="$1"
    local harness_rel="Harness.${mode^}.dll"
    local corpus_dir="$PROJECT_ROOT/build/corpus/$mode"
    local coverlet_log="$COVERAGE_DIR/${mode}_coverlet.log"
    local seed seed_name xml_output ok

    : > "$coverlet_log"

    for seed in $(find "$corpus_dir" -type f 2>/dev/null | sort); do
        seed_name=$(basename "$seed" .bin)
        xml_output="$COVERAGE_DIR/${mode}_${seed_name}.xml"

        cd "$COV_APP"
        ok=true
        "$PROJECT_ROOT/tools/bin/coverlet" "$COV_APP" \
            --target "$DOTNET_ROOT/dotnet" \
            --targetargs "$COV_APP/$harness_rel $seed" \
            --format opencover \
            --output "$xml_output" \
            >> "$coverlet_log" 2>&1 || ok=false
        cd "$PROJECT_ROOT"

        if [[ "$ok" != "true" ]] || [[ ! -s "$xml_output" ]]; then
            rm -f "$xml_output"
            echo "  ПРЕДУПРЕЖДЕНИЕ: coverlet не собрал покрытие для $seed_name ($mode)."
            continue
        fi
        COLLECTED_XML+=("$xml_output")
    done
}

echo ""
echo "=== Сбор покрытия по режимам (все сиды корпуса) ==="
for mode in reader writer differential; do
    echo "--- Режим: $mode ---"
    run_coverlet_mode "$mode"
    echo "  Собрано XML: $(ls "$COVERAGE_DIR/${mode}_"*.xml 2>/dev/null | wc -l) из 10"
done

# ------------------------------------------------------------
# Контроль: библиотека действительно попала в отчёт.
# ВАЖНО: OpenCover XML хранит имя модуля в ЭЛЕМЕНТЕ <ModuleName>,
# а не в атрибуте 'module name="..."' — прежний шаблон не матчился
# никогда и давал ложный отказ при фактически собранном покрытии.
# ------------------------------------------------------------
LIB_FOUND=0
for f in "${COLLECTED_XML[@]}"; do
    if grep -q '<ModuleName>Newtonsoft.Json.Bson</ModuleName>' "$f" 2>/dev/null; then
        LIB_FOUND=1
        break
    fi
done

if [[ ${#COLLECTED_XML[@]} -eq 0 ]] || [[ "$LIB_FOUND" -eq 0 ]]; then
    echo "ОШИБКА: Модуль Newtonsoft.Json.Bson не попал в покрытие. HTML не генерируется."
    echo "  Диагностика: tail -n 40 $COVERAGE_DIR/reader_coverlet.log"
    echo "  Модули в XML: grep -ho '<ModuleName>[^<]*</ModuleName>' $COVERAGE_DIR/reader_seed_0001.xml | sort -u"
    exit 1
fi
echo "[OK] Модуль Newtonsoft.Json.Bson присутствует в отчёте покрытия."

echo ""
echo "=== Генерация HTML-отчёта ==="
REPORTS_LIST=$(IFS=';'; echo "${COLLECTED_XML[*]}")
echo "  Отчётов для объединения: ${#COLLECTED_XML[@]} шт."

# classfilters оставляет в HTML только классы библиотеки
"$PROJECT_ROOT/tools/bin/reportgenerator" \
    "-reports:$REPORTS_LIST" \
    "-targetdir:$COVERAGE_DIR/html" \
    "-reporttypes:Html" \
    "-classfilters:+Newtonsoft.Json.Bson.*"

echo "  [OK] HTML-отчёт сгенерирован: $COVERAGE_DIR/html/index.html"
echo ""
echo "=== Сбор покрытия завершён ==="
echo "HTML-отчёт: $COVERAGE_DIR/html/index.html"
