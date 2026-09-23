#!/usr/bin/env bash
# open_results.sh
# Просмотр результатов прогона: статистика фаззинга, классы крашей,
# открытие логов (final_report.md, summary.md, all_crashes.log) и HTML-отчёта покрытия.
# Использование:
#   ./open_results.sh                 # последний прогон (RUN_ID из окружения или latest.txt)
#   ./open_results.sh --list          # список всех прогонов
#   ./open_results.sh --run-id <ID>   # открыть конкретный прогон
#   ./open_results.sh --stats-only    # только статистика в stdout, без открытия
#   ./open_results.sh --no-browser    # не открывать HTML в браузере (для SSH)

set -uo pipefail
cd "$(dirname "$0")"

# ============================================================
# Цвета для терминала
# ============================================================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

print_header() {
    echo ""
    echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════════════════${NC}"
    echo -e "${CYAN}${BOLD}  $1${NC}"
    echo -e "${CYAN}${BOLD}══════════════════════════════════════════════════════════════${NC}"
}

print_section() { echo -e "\n${BLUE}${BOLD}▸ $1${NC}"; }
print_ok()      { echo -e "  ${GREEN}[OK]${NC} $1"; }
print_missing() { echo -e "  ${YELLOW}[—]${NC} $1 ${DIM}(не найдено)${NC}"; }
print_info()    { echo -e "  ${DIM}→${NC} $1"; }
print_stat()    { printf "  ${BOLD}%-18s${NC} %s\n" "$1" "$2"; }

# ============================================================
# Парсинг аргументов; RUN_ID может прийти из окружения (run_all.sh)
# ============================================================
RUN_ID="${RUN_ID:-}"
ACTION="open"
OPEN_BROWSER=1

while [[ $# -gt 0 ]]; do
    case "$1" in
        --list|-l)      ACTION="list"; shift ;;
        --run-id|-r)    RUN_ID="$2"; shift 2 ;;
        --stats-only|-s) ACTION="stats"; shift ;;
        --no-browser|-n) OPEN_BROWSER=0; shift ;;
        --help|-h)
            echo "Использование: ./open_results.sh [опции]"
            echo "  --list, -l           Список всех доступных прогонов"
            echo "  --run-id, -r <ID>    Открыть конкретный прогон"
            echo "  --stats-only, -s     Только статистика, без открытия файлов"
            echo "  --no-browser, -n     Не открывать HTML в браузере (для SSH)"
            exit 0
            ;;
        *) echo -e "${RED}Неизвестная опция: $1${NC} (--help для справки)"; exit 1 ;;
    esac
done

# ============================================================
# --list: список прогонов
# ============================================================
if [[ "$ACTION" == "list" ]]; then
    print_header "Доступные прогоны"
    if [[ ! -d "results" ]]; then
        echo -e "${YELLOW}Каталог results/ не найден. Запустите сначала ./run_all.sh${NC}"
        exit 0
    fi
    LATEST=""
    [[ -f "results/latest.txt" ]] && LATEST=$(cat results/latest.txt 2>/dev/null || true)
    FOUND=0
    for dir in results/*/; do
        [[ -d "$dir" ]] || continue
        id=$(basename "$dir")
        FOUND=1
        has_final="·"; has_crash="·"; has_cov="·"; has_sig="·"
        [[ -f "$dir/final_report.md" ]] && has_final="${GREEN}✓${NC}"
        [[ -f "$dir/crash_analysis_report/summary.md" ]] && has_crash="${GREEN}✓${NC}"
        [[ -f "$dir/crash_analysis_report/unique_signatures.txt" ]] && has_sig="${GREEN}✓${NC}"
        [[ -f "$dir/coverage/html/index.html" ]] && has_cov="${GREEN}✓${NC}"
        marker="  "
        [[ "$id" == "$LATEST" ]] && marker="${YELLOW}→ ${NC}"
        echo -e "  ${marker}${BOLD}$id${NC}  [final:$has_final crash:$has_crash sig:$has_sig coverage:$has_cov]"
    done
    [[ "$FOUND" -eq 0 ]] && echo -e "${YELLOW}Прогонов не найдено${NC}"
    exit 0
fi

# ============================================================
# Определение RUN_ID (окружение → latest.txt)
# ============================================================
if [[ -z "$RUN_ID" && -f "results/latest.txt" ]]; then
    RUN_ID=$(cat results/latest.txt 2>/dev/null | tr -d '[:space:]')
fi
if [[ -z "$RUN_ID" ]]; then
    echo -e "${RED}ОШИБКА: RUN_ID не определён.${NC} Используйте --list или --run-id <ID>."
    exit 1
fi

RESULTS_DIR="results/$RUN_ID"
if [[ ! -d "$RESULTS_DIR" ]]; then
    echo -e "${RED}ОШИБКА: Каталог результатов не найден: $RESULTS_DIR${NC}"
    exit 1
fi

print_header "Результаты прогона: $RUN_ID"
print_info "Каталог: $RESULTS_DIR/"

# ============================================================
# Статистика фаззинга по режимам
# ============================================================
print_section "Статистика фаззинга"

get_stat() {
    local file="$1" key="$2"
    [[ -f "$file" ]] || return 0
    grep -m1 "^${key}" "$file" 2>/dev/null | awk -F: '{print $2}' | tr -d '[:space:]' | head -n1
}

for mode in reader writer differential; do
    echo -e "  ${MAGENTA}${BOLD}[$mode]${NC}"
    stats_file=""
    if [[ -f "$RESULTS_DIR/$mode/fuzzer_stats" ]]; then
        stats_file="$RESULTS_DIR/$mode/fuzzer_stats"
    elif [[ -f "$RESULTS_DIR/$mode/default/fuzzer_stats" ]]; then
        stats_file="$RESULTS_DIR/$mode/default/fuzzer_stats"
    fi
    if [[ -z "$stats_file" ]]; then
        print_missing "fuzzer_stats"
        continue
    fi
    print_stat "execs:"            "$(get_stat "$stats_file" "execs_done")"
    print_stat "execs/sec:"        "$(get_stat "$stats_file" "execs_per_sec")"
    print_stat "paths total:"      "$(get_stat "$stats_file" "paths_total")"
    print_stat "unique crashes:"   "$(get_stat "$stats_file" "unique_crashes")"
    print_stat "unique hangs:"     "$(get_stat "$stats_file" "unique_hangs")"
done

# ============================================================
# Анализ крашей: сводная таблица
# ============================================================
print_section "Анализ крашей"
CRASH_SUMMARY="$RESULTS_DIR/crash_analysis_report/summary.md"
if [[ -f "$CRASH_SUMMARY" ]]; then
    grep -E "^\|" "$CRASH_SUMMARY" | head -n 5 | while IFS= read -r line; do
        echo -e "  ${DIM}$line${NC}"
    done
    detail_count=$(find "$RESULTS_DIR/crash_analysis_report" -name "*_crash_*.txt" 2>/dev/null | wc -l)
    [[ "$detail_count" -gt 0 ]] && print_info "Детальных отчётов по крашам: $detail_count"
else
    print_missing "crash_analysis_report/summary.md"
fi

# ============================================================
# Классы крашей: уникальные сигнатуры (из repro_all_crashes.sh)
# ============================================================
print_section "Классы крашей (уникальные сигнатуры)"
SIGFILE="$RESULTS_DIR/crash_analysis_report/unique_signatures.txt"
if [[ -f "$SIGFILE" && -s "$SIGFILE" ]]; then
    print_info "count | sig | type | representative | first_line"
    column -t -s $'\t' "$SIGFILE" 2>/dev/null | head -n 10 | sed 's/^/  /' || head -n 10 "$SIGFILE" | sed 's/^/  /'
else
    print_missing "unique_signatures.txt"
fi

# ============================================================
# Покрытие кода
# ============================================================
print_section "Покрытие кода"
COVERAGE_HTML="$RESULTS_DIR/coverage/html/index.html"
if [[ -f "$COVERAGE_HTML" ]]; then
    print_ok "HTML-отчёт покрытия доступен"
else
    print_missing "coverage/html/index.html"
fi

# ============================================================
# Сводный отчёт
# ============================================================
print_section "Сводный отчёт"
FINAL_REPORT="$RESULTS_DIR/final_report.md"
if [[ -f "$FINAL_REPORT" ]]; then
    print_ok "final_report.md ($(wc -c < "$FINAL_REPORT") байт)"
else
    print_missing "final_report.md"
fi

if [[ "$ACTION" == "stats" ]]; then
    echo -e "\n${DIM}Режим --stats-only: файлы не открываются${NC}"
    exit 0
fi

# ============================================================
# Открытие отчётов и логов
# ============================================================

# Просмотр файла через less ТОЛЬКО в интерактивном терминале;
# в неинтерактивном режиме (nohup/CI) — пропускаем, чтобы не блокировать конвейер
view_file() {
    local file="$1" title="$2"
    if [[ ! -f "$file" ]]; then
        print_missing "$title"
        return
    fi
    if [[ ! -t 0 ]]; then
        print_info "Неинтерактивный режим: $title не открыт ($file)"
        return
    fi
    print_ok "$title"
    echo -e "  ${DIM}Space=вниз, b=вверх, /=поиск, q=выход${NC}"
    less -R -f "$file"
}

# 1. HTML-отчёт покрытия — в браузер (фоновый процесс)
if [[ "$OPEN_BROWSER" -eq 1 && -f "$COVERAGE_HTML" ]]; then
    abs_path="$(cd "$(dirname "$COVERAGE_HTML")" && pwd)/$(basename "$COVERAGE_HTML")"
    if command -v xdg-open &> /dev/null; then
        print_ok "Открываю HTML-отчёт покрытия в браузере..."
        xdg-open "$abs_path" &> /dev/null &
    else
        print_info "Браузер не найден (xdg-open). HTML-отчёт: $abs_path"
    fi
elif [[ "$OPEN_BROWSER" -eq 1 ]]; then
    print_missing "HTML-отчёт покрытия (нечего открывать)"
fi

# 2. Логи и отчёты — последовательный просмотр через less
echo -e "\n${BOLD}Просмотр логов и отчётов (Enter — открыть, Ctrl+C — пропустить):${NC}"

read -rp "Нажмите Enter для просмотра final_report.md..." 2>/dev/null
view_file "$FINAL_REPORT" "final_report.md"

read -rp "Нажмите Enter для просмотра summary.md (анализ крашей)..." 2>/dev/null
view_file "$CRASH_SUMMARY" "crash_analysis_report/summary.md"

read -rp "Нажмите Enter для просмотра all_crashes.log (единый лог воспроизведений)..." 2>/dev/null
view_file "$RESULTS_DIR/crash_analysis_report/all_crashes.log" "crash_analysis_report/all_crashes.log"

# ============================================================
# Финальные подсказки
# ============================================================
print_header "Дальнейшие действия"
print_info "Все воспроизведения крашей: less $RESULTS_DIR/crash_analysis_report/all_crashes.log"
print_info "Классы крашей:             cat $RESULTS_DIR/crash_analysis_report/unique_signatures.txt"
print_info "Индекс крашей (TSV):       less $RESULTS_DIR/crash_analysis_report/crash_index.tsv"
print_info "HTML-покрытие:             $COVERAGE_HTML"
echo -e "\n${GREEN}${BOLD}Готово.${NC}"
