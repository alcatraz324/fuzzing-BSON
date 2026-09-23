#!/usr/bin/env bash
# scripts/fuzz.sh
# Запуск фаззинга AFL++ для трёх режимов: reader, writer, differential

set -euo pipefail
cd "$(dirname "$0")/.."

source config/project.env

export DOTNET_ROOT="$PROJECT_ROOT/tools/dotnet"
export PATH="$DOTNET_ROOT:$PROJECT_ROOT/tools/bin:$PATH"

# ВАЖНО: SharpFuzz использует shared memory, а не нативную AFL-инструментацию.
export AFL_SKIP_BIN_CHECK=1

# Отключаем фичи .NET, несовместимые с fork() в AFL++ fork server:
# - TieredCompilation: JIT-компиляция использует много памяти при fork
# - gcServer: серверный GC требует больших непрерывных блоков памяти
# - gcConcurrent: параллельный GC создаёт потоки, теряющиеся при fork
# - Diagnostics: диагностические пайпы конфликтуют с AFL pipe handles
export DOTNET_EnableDiagnostics=0
export DOTNET_TieredCompilation=0
export DOTNET_gcServer=0
export DOTNET_gcConcurrent=0

echo "=== Подготовка к фаззингу ==="

if ! command -v afl-fuzz &> /dev/null; then
    echo "ОШИБКА: afl-fuzz не найден в PATH."
    exit 1
fi
echo "[OK] afl-fuzz найден."

if [[ ! -f "$PROJECT_ROOT/build/bson.dict" ]]; then
    echo "ОШИБКА: Словарь build/bson.dict не найден."
    exit 1
fi
echo "[OK] Словарь build/bson.dict найден."

for mode in reader writer differential; do
    corpus_dir="$PROJECT_ROOT/build/corpus/$mode"
    if [[ ! -d "$corpus_dir" ]] || [[ -z "$(ls -A "$corpus_dir" 2>/dev/null)" ]]; then
        echo "ОШИБКА: Каталог корпуса $corpus_dir пуст."
        exit 1
    fi
done
echo "[OK] Корпус найден."

MISSING_HARNESS=0
for mode in reader writer differential; do
    harness_path="$PROJECT_ROOT/build/Harness.${mode^}.dll"
    if [[ ! -f "$harness_path" ]]; then
        echo "ОШИБКА: Харнесс не найден: $harness_path"
        MISSING_HARNESS=1
    fi
done
if [[ "$MISSING_HARNESS" -ne 0 ]]; then
    echo "Харнесс не найден. Соберите его через build_harness.sh."
    exit 1
fi
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

for mode in reader writer differential; do
    mkdir -p "$PROJECT_ROOT/results/$RUN_ID/$mode"
done

echo ""
echo "=== Запуск фаззинга ==="
echo "RUN_ID: $RUN_ID"
echo ""

print_fuzzer_stats() {
    local output_dir="$1"
    local stats_file="$output_dir/fuzzer_stats"
    if [[ ! -f "$stats_file" ]] && [[ -f "$output_dir/default/fuzzer_stats" ]]; then
        stats_file="$output_dir/default/fuzzer_stats"
    fi
    if [[ ! -f "$stats_file" ]]; then
        echo "  Статистика недоступна."
        return
    fi
    echo "  --- Статистика ---"
    get_stat() { grep "^$1" "$stats_file" 2>/dev/null | awk '{print $NF}' | head -n1; }
    echo "  execs_done: $(get_stat 'execs_done')"
    echo "  execs_per_sec: $(get_stat 'execs_per_sec')"
    echo "  unique_crashes: $(get_stat 'unique_crashes')"
    echo "  unique_hangs: $(get_stat 'unique_hangs')"
}

for mode in reader writer differential; do
    echo "=== Фаззинг режима: $mode ==="
    harness_name="Harness.${mode^}"
    harness_path="$PROJECT_ROOT/build/${harness_name}.dll"
    corpus_dir="$PROJECT_ROOT/build/corpus/$mode"
    output_dir="$PROJECT_ROOT/results/$RUN_ID/$mode"

    # ВАЖНО: -m none — .NET runtime требует большой объём виртуальной памяти
    # для GC heap. При fork() в AFL++ fork server setrlimit ограничивает
    # виртуальную память, и CoreCLR падает с E_OUTOFMEMORY (0x8007000E).
    # -m none отключает memory limit, позволяя .NET зарезервировать нужный объём.
    # @@ убран — SharpFuzz использует fork server, данные через stdin
    afl-fuzz \
        -i "$corpus_dir" \
        -o "$output_dir" \
        -m none \
        -t "$TIMEOUT_MS" \
        -x "$PROJECT_ROOT/build/bson.dict" \
        -V "$FUZZ_TIME_SECONDS" \
        -- "$DOTNET_ROOT/dotnet" "$harness_path" || true

    print_fuzzer_stats "$output_dir"
    echo "----------------------------------------"
done

echo "=== Фаззинг завершён ==="
