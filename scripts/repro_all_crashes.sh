#!/usr/bin/env bash
# scripts/repro_all_crashes.sh
# Сбор ВСЕХ крашей прогона, сортировка, воспроизведение и запись
# единого лога + индекса + уникальных сигнатур для анализа.
# Использование:
#   ./scripts/repro_all_crashes.sh            # последний прогон (latest.txt)
#   ./scripts/repro_all_crashes.sh <RUN_ID>   # конкретный прогон

set -euo pipefail
cd "$(dirname "$0")/.."

source config/project.env

export DOTNET_ROOT="$PROJECT_ROOT/tools/dotnet"
export PATH="$DOTNET_ROOT:$PROJECT_ROOT/tools/bin:$PATH"

# ------------------------------------------------------------
# Определение RUN_ID
# ------------------------------------------------------------
RUN_ID="${1:-}"
if [[ -z "$RUN_ID" ]]; then
    if [[ -f "$PROJECT_ROOT/results/latest.txt" ]]; then
        RUN_ID=$(cat "$PROJECT_ROOT/results/latest.txt")
    else
        echo "ОШИБКА: RUN_ID не задан и results/latest.txt не найден."
        exit 1
    fi
fi

if [[ ! -d "$PROJECT_ROOT/results/$RUN_ID" ]]; then
    echo "ОШИБКА: Каталог прогона не найден: results/$RUN_ID"
    exit 1
fi

REPORT_DIR="$PROJECT_ROOT/results/$RUN_ID/crash_analysis_report"
mkdir -p "$REPORT_DIR"

LOG="$REPORT_DIR/all_crashes.log"        # единый лог всех воспроизведений
INDEX="$REPORT_DIR/crash_index.tsv"      # машиночитаемый индекс (TAB-разделитель)
SIGFILE="$REPORT_DIR/unique_signatures.txt"  # уникальные классы ошибок

: > "$LOG"
printf 'mode\texit_code\ttype\tsignature\tfile\n' > "$INDEX"

echo "=== Сбор и воспроизведение всех крашей: $RUN_ID ==="

# ------------------------------------------------------------
# Вспомогательные функции
# ------------------------------------------------------------
get_crash_type() {
    case "$1" in
        139) echo "SIGSEGV" ;;
        134) echo "SIGABRT" ;;
        137) echo "SIGKILL/OOM" ;;
        143) echo "SIGTERM/timeout" ;;
        1)   echo "DOTNET_EXCEPTION" ;;
        0)   echo "NOT_REPRODUCED" ;;
        *)   echo "CODE_$1" ;;
    esac
}

# Нормализация вывода для сигнатуры: убираем цифры и пути,
# чтобы одинаковые по сути ошибки (разные адреса/ids) попали в один класс
normalize_sig() {
    tr -d '\r' | sed -E 's#[0-9]+#N#g; s#/home/[^ ]*#PATH#g; s#id:[^ ,]*#ID#g' | head -c 300
}

# Агрегаты по сигнатурам
declare -A SIG_COUNT SIG_TYPE SIG_REP SIG_FIRST

TOTAL=0

# ------------------------------------------------------------
# Проход по режимам и каталогам крашей (сортировка: режим → id AFL++)
# ------------------------------------------------------------
for mode in reader writer differential; do
    harness="$PROJECT_ROOT/build/Harness.${mode^}.dll"
    if [[ ! -f "$harness" ]]; then
        echo "ПРЕДУПРЕЖДЕНИЕ: харнесс $harness не найден, режим $mode пропущен."
        continue
    fi

    for dir in "$PROJECT_ROOT/results/$RUN_ID/$mode/crashes" \
               "$PROJECT_ROOT/results/$RUN_ID/$mode/default/crashes"; do
        [[ -d "$dir" ]] || continue

        while IFS= read -r f; do
            TOTAL=$((TOTAL + 1))

            # Воспроизведение с таймаутом; вывод и код возврата захватываем
            set +e
            out=$(timeout 5 "$DOTNET_ROOT/dotnet" "$harness" "$f" 2>&1)
            code=$?
            set -e

            type=$(get_crash_type "$code")
            sig=$(printf '%s|%s' "$code" "$out" | normalize_sig | md5sum | cut -c1-8)
            first_line=$(printf '%s' "$out" | head -n 1 | tr -d '\r\t' | cut -c1-120)

            # Единый лог: блок с метаданными + полный вывод воспроизведения
            {
                echo "==== CRASH #$(printf '%04d' "$TOTAL") | mode=$mode | exit=$code ($type) | sig=$sig | file=$f ===="
                printf '%s\n' "$out"
                echo ""
            } >> "$LOG"

            # Индекс (TAB; имена AFL++ содержат запятые, поэтому не CSV)
            printf '%s\t%s\t%s\t%s\t%s\n' "$mode" "$code" "$type" "$sig" "$f" >> "$INDEX"

            # Агрегация по сигнатуре
            SIG_COUNT[$sig]=$(( ${SIG_COUNT[$sig]:-0} + 1 ))
            SIG_TYPE[$sig]="$type"
            SIG_FIRST[$sig]="$first_line"
            if [[ -z "${SIG_REP[$sig]:-}" ]]; then
                SIG_REP[$sig]="$f"
            fi
        done < <(find "$dir" -maxdepth 1 -type f | sort)
    done
done

# ------------------------------------------------------------
# Уникальные сигнатуры (классы ошибок), сортировка по убыванию частоты
# ------------------------------------------------------------
: > "$SIGFILE"
for sig in "${!SIG_COUNT[@]}"; do
    printf '%s\t%s\t%s\t%s\t%s\n' \
        "${SIG_COUNT[$sig]}" "$sig" "${SIG_TYPE[$sig]}" "${SIG_REP[$sig]}" "${SIG_FIRST[$sig]}"
done | sort -rn >> "$SIGFILE"

echo ""
echo "=== Итог ==="
echo "Всего крашей воспроизведено: $TOTAL"
echo "Уникальных классов ошибок:   $(wc -l < "$SIGFILE")"
echo ""
echo "Классы ошибок (count, sig, type, representative, first_line):"
column -t -s $'\t' "$SIGFILE" 2>/dev/null || cat "$SIGFILE"
echo ""
echo "Единый лог:      $LOG"
echo "Индекс крашей:   $INDEX"
echo "Сигнатуры:       $SIGFILE"
echo "=== Сбор завершён ==="
