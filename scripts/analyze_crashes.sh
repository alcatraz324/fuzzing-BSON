#!/usr/bin/env bash
# scripts/analyze_crashes.sh
set -euo pipefail
cd "$(dirname "$0")/.."
source config/project.env
export DOTNET_ROOT="$PROJECT_ROOT/tools/dotnet"
export PATH="$DOTNET_ROOT:$PROJECT_ROOT/tools/bin:$PATH"

echo "=== Анализ крашей ==="

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
    if [[ ! -f "$PROJECT_ROOT/build/Harness.${mode^}.dll" ]]; then
        echo "ОШИБКА: Харнесс не найден."
        exit 1
    fi
done

REPORT_DIR="$PROJECT_ROOT/results/$RUN_ID/crash_analysis_report"
mkdir -p "$REPORT_DIR"

get_crash_type() {
    case $1 in
        139) echo "SIGSEGV" ;; 134) echo "SIGABRT" ;; 137) echo "OOM" ;;
        143) echo "Timeout" ;; 1) echo ".NET Exception" ;; 0) echo "Не воспроизвёлся" ;;
        *) echo "Код: $1" ;;
    esac
}

find_crash_dir() {
    if [[ -d "$1/crashes" ]] && [[ -n "$(ls -A "$1/crashes" 2>/dev/null)" ]]; then echo "$1/crashes"; return; fi
    if [[ -d "$1/default/crashes" ]] && [[ -n "$(ls -A "$1/default/crashes" 2>/dev/null)" ]]; then echo "$1/default/crashes"; return; fi
    echo ""
}

declare -A TOTAL SEGV ABRT OOM TIMEOUT FAKE OTHER
for mode in reader writer differential; do
    TOTAL[$mode]=0; SEGV[$mode]=0; ABRT[$mode]=0; OOM[$mode]=0
    TIMEOUT[$mode]=0; FAKE[$mode]=0; OTHER[$mode]=0
done

for mode in reader writer differential; do
    echo "--- Режим: $mode ---"
    harness_path="$PROJECT_ROOT/build/Harness.${mode^}.dll"
    crashes_dir=$(find_crash_dir "$PROJECT_ROOT/results/$RUN_ID/$mode")
    if [[ -z "$crashes_dir" ]]; then continue; fi

    n=0
    for crash_file in "$crashes_dir"/*; do
        [[ -f "$crash_file" ]] || continue
        n=$((n+1))
        TOTAL[$mode]=$((TOTAL[$mode]+1))

        # Прямой файловый аргумент (standalone режим харнесса)
        set +e
        output=$(timeout 5 "$DOTNET_ROOT/dotnet" "$harness_path" "$crash_file" 2>&1)
        code=$?
        set -e

        type=$(get_crash_type "$code")
        case $code in
            139) SEGV[$mode]=$((SEGV[$mode]+1)) ;; 134) ABRT[$mode]=$((ABRT[$mode]+1)) ;;
            137) OOM[$mode]=$((OOM[$mode]+1)) ;; 143) TIMEOUT[$mode]=$((TIMEOUT[$mode]+1)) ;;
            0) FAKE[$mode]=$((FAKE[$mode]+1)) ;; *) OTHER[$mode]=$((OTHER[$mode]+1)) ;;
        esac

        { echo "Режим: $mode"; echo "Файл: $crash_file"; echo "Exit: $code ($type)"; echo "$output"; } \
            > "$REPORT_DIR/${mode}_crash_${n}.txt"
    done
done

{
    echo "# Анализ крашей — $RUN_ID"
    echo ""
    echo "| Режим | Всего | SIGSEGV | SIGABRT | OOM | Timeout | Ложные | Прочие |"
    echo "|-------|-------|---------|---------|-----|---------|--------|--------|"
    for mode in reader writer differential; do
        echo "| $mode | ${TOTAL[$mode]} | ${SEGV[$mode]} | ${ABRT[$mode]} | ${OOM[$mode]} | ${TIMEOUT[$mode]} | ${FAKE[$mode]} | ${OTHER[$mode]} |"
    done
} > "$REPORT_DIR/summary.md"

echo "[OK] Отчёт: $REPORT_DIR/summary.md"
