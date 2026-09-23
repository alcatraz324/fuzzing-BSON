#!/usr/bin/env python3
# scripts/generate_report.py
# Генерация сводного отчёта по результатам фаззинга

"""Агрегация результатов фаззинга в единый сводный отчёт.

Читает и объединяет данные из:
  - Статистики фаззера (fuzzer_stats) для каждого режима
  - Анализа крашей (crash_analysis_report/summary.md)
  - Метрик покрытия кода (coverage XML и HTML)

Результат сохраняется в results/$RUN_ID/final_report.md.
Код не падает при отсутствии отдельных файлов — обрабатывает всё корректно.
"""

import argparse
import os
import re
import sys
from datetime import datetime
from typing import Dict, List, Optional


class FuzzingReportGenerator:
    """Генератор сводного отчёта по результатам фаззинга."""

    # Режимы фаззинга
    MODES: List[str] = ["reader", "writer", "differential"]

    # Ключи из fuzzer_stats, которые мы парсим
    FUZZER_STAT_KEYS: List[str] = [
        "execs_done", "execs_per_sec", "unique_crashes",
        "total_crashes", "unique_hangs", "last_update", "paths_total"
    ]

    def __init__(self, project_root: str, run_id: str) -> None:
        """Инициализация генератора.

        :param project_root: корневая директория проекта
        :param run_id: идентификатор запуска фаззинга
        """
        self.project_root = project_root
        self.run_id = run_id
        self.results_dir = os.path.join(project_root, "results", run_id)

    def find_fuzzer_stats(self, mode: str) -> str:
        """Ищет файл fuzzer_stats с фолбэком на подкаталог default/.

        :param mode: режим фаззинга (reader, writer, differential)
        :return: путь к файлу или пустая строка, если не найден
        """
        mode_dir = os.path.join(self.results_dir, mode)
        primary = os.path.join(mode_dir, "fuzzer_stats")
        if os.path.isfile(primary):
            return primary
        fallback = os.path.join(mode_dir, "default", "fuzzer_stats")
        if os.path.isfile(fallback):
            return fallback
        return ""

    def parse_fuzzer_stats(self, mode: str) -> Dict[str, str]:
        """Парсит файл fuzzer_stats AFL++ для заданного режима.

        Формат файла: строки вида 'ключ        : значение'.

        :param mode: режим фаззинга
        :return: словарь с распарсенными значениями
        """
        stats_path = self.find_fuzzer_stats(mode)
        if not stats_path:
            return {}

        stats: Dict[str, str] = {}
        try:
            with open(stats_path, "r", encoding="utf-8", errors="replace") as f:
                for line in f:
                    line = line.strip()
                    if not line or line.startswith("#"):
                        continue
                    if ":" in line:
                        key, _, value = line.partition(":")
                        key = key.strip()
                        value = value.strip()
                        if key in self.FUZZER_STAT_KEYS:
                            stats[key] = value
        except (OSError, IOError):
            return {}

        return stats

    def read_crash_summary(self) -> str:
        """Читает содержимое сводного отчёта анализа крашей.

        :return: содержимое файла или пустая строка, если не найден
        """
        summary_path = os.path.join(
            self.results_dir, "crash_analysis_report", "summary.md"
        )
        if not os.path.isfile(summary_path):
            return ""
        try:
            with open(summary_path, "r", encoding="utf-8", errors="replace") as f:
                return f.read()
        except (OSError, IOError):
            return ""

    def check_coverage_xml(self, mode: str) -> bool:
        """Проверяет наличие непустого XML-файла покрытия для режима.

        :param mode: режим фаззинга
        :return: True, если файл существует и не пустой
        """
        xml_path = os.path.join(self.results_dir, "coverage", f"{mode}.xml")
        return os.path.isfile(xml_path) and os.path.getsize(xml_path) > 0

    def check_coverage_html(self) -> bool:
        """Проверяет наличие HTML-отчёта покрытия.

        :return: True, если index.html существует
        """
        html_path = os.path.join(
            self.results_dir, "coverage", "html", "index.html"
        )
        return os.path.isfile(html_path)

    def parse_project_env(self) -> Dict[str, str]:
        """Парсит переменные из config/project.env.

        Извлекает значения FUZZ_TIME_SECONDS, MEMORY_LIMIT_MB, TIMEOUT_MS.

        :return: словарь с найденными значениями
        """
        env_path = os.path.join(self.project_root, "config", "project.env")
        config: Dict[str, str] = {}
        if not os.path.isfile(env_path):
            return config

        try:
            with open(env_path, "r", encoding="utf-8", errors="replace") as f:
                content = f.read()
        except (OSError, IOError):
            return config

        for var in ["FUZZ_TIME_SECONDS", "MEMORY_LIMIT_MB", "TIMEOUT_MS"]:
            # Паттерн: VAR="${VAR:-default}"
            pattern1 = rf'{var}="\$\{{{var}:-(\d+)\}}"'
            match = re.search(pattern1, content)
            if match:
                config[var] = match.group(1)
                continue
            # Паттерн: VAR=default или VAR="default"
            pattern2 = rf'^{var}="?(\d+)"?'
            match = re.search(pattern2, content, re.MULTILINE)
            if match:
                config[var] = match.group(1)

        return config

    @staticmethod
    def safe_int(value: str, default: int = 0) -> int:
        """Безопасно конвертирует строку в целое число.

        :param value: строковое значение
        :param default: значение по умолчанию при ошибке
        :return: целое число
        """
        try:
            return int(value.strip())
        except (ValueError, TypeError, AttributeError):
            return default

    @staticmethod
    def safe_float(value: str, default: float = 0.0) -> float:
        """Безопасно конвертирует строку в число с плавающей точкой.

        :param value: строковое значение
        :param default: значение по умолчанию при ошибке
        :return: число с плавающей точкой
        """
        try:
            return float(value.strip())
        except (ValueError, TypeError, AttributeError):
            return default

    def get_stat(self, stats: Dict[str, str], key: str, default: str = "Недоступно") -> str:
        """Извлекает значение из словаря статистики с дефолтом.

        :param stats: словарь со статистикой
        :param key: ключ для поиска
        :param default: значение по умолчанию
        :return: найденное значение или дефолт
        """
        value = stats.get(key, "").strip()
        return value if value else default

    def generate_recommendations(
        self, fuzzing_data: Dict[str, Dict[str, str]], has_coverage: bool
    ) -> List[str]:
        """Генерирует список рекомендаций на основе результатов.

        :param fuzzing_data: данные фаззинга по режимам
        :param has_coverage: есть ли данные о покрытии
        :return: список строк-рекомендаций
        """
        recommendations: List[str] = []
        has_crashes = False
        has_hangs = False
        low_speed = False

        for mode in self.MODES:
            stats = fuzzing_data.get(mode, {})
            unique_crashes = self.safe_int(self.get_stat(stats, "unique_crashes", "0"))
            total_crashes = self.safe_int(self.get_stat(stats, "total_crashes", "0"))
            unique_hangs = self.safe_int(self.get_stat(stats, "unique_hangs", "0"))
            execs_per_sec = self.safe_float(self.get_stat(stats, "execs_per_sec", "0"))

            if unique_crashes > 0 or total_crashes > 0:
                has_crashes = True
            if unique_hangs > 0:
                has_hangs = True
            if 0 < execs_per_sec < 10:
                low_speed = True

        if has_crashes:
            recommendations.append(
                "- Изучите детали в `crash_analysis_report/`"
            )
        if not has_coverage:
            recommendations.append(
                "- Запустите `./scripts/coverage.sh` для сбора метрик покрытия"
            )
        if has_hangs:
            recommendations.append(
                "- Проверьте таймауты, возможно есть бесконечные циклы"
            )
        if low_speed:
            recommendations.append(
                "- Низкая скорость фаззинга, проверьте производительность харнесса"
            )
        if not recommendations:
            recommendations.append("- Результаты выглядят удовлетворительно")

        return recommendations

    def generate_report(self) -> str:
        """Генерирует полный текст сводного отчёта в формате Markdown.

        :return: содержимое отчёта
        """
        lines: List[str] = []
        generation_date = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

        # Заголовок
        lines.append(f"# Сводный отчёт по фаззингу — {self.run_id}")
        lines.append("")
        lines.append(f"**Дата и время генерации:** {generation_date}")
        lines.append("")

        # Раздел "Конфигурация"
        config = self.parse_project_env()
        lines.append("## Конфигурация")
        lines.append("")
        lines.append("| Параметр | Значение |")
        lines.append("|----------|----------|")
        lines.append(
            f"| Время фаззинга (сек) | {config.get('FUZZ_TIME_SECONDS', 'Не определено')} |"
        )
        lines.append(
            f"| Лимит памяти (МБ) | {config.get('MEMORY_LIMIT_MB', 'Не определено')} |"
        )
        lines.append(
            f"| Таймаут (мс) | {config.get('TIMEOUT_MS', 'Не определено')} |"
        )
        lines.append("")

        # Раздел "Результаты фаззинга"
        lines.append("## Результаты фаззинга")
        lines.append("")
        lines.append(
            "| Режим | Execs | Exec/s | Уник. крашей | Всего крашей | Зависания | Покрытие |"
        )
        lines.append(
            "|-------|-------|--------|-------------|-------------|-----------|----------|"
        )

        fuzzing_data: Dict[str, Dict[str, str]] = {}
        for mode in self.MODES:
            stats = self.parse_fuzzer_stats(mode)
            fuzzing_data[mode] = stats

            execs = self.get_stat(stats, "execs_done")
            execs_per_sec = self.get_stat(stats, "execs_per_sec")
            unique_crashes = self.get_stat(stats, "unique_crashes")
            total_crashes = self.get_stat(stats, "total_crashes")
            unique_hangs = self.get_stat(stats, "unique_hangs")
            coverage_status = "Да" if self.check_coverage_xml(mode) else "Нет"

            lines.append(
                f"| {mode} | {execs} | {execs_per_sec} | {unique_crashes} "
                f"| {total_crashes} | {unique_hangs} | {coverage_status} |"
            )
        lines.append("")

        # Раздел "Анализ крашей"
        lines.append("## Анализ крашей")
        lines.append("")
        crash_summary = self.read_crash_summary()
        if crash_summary:
            lines.append(crash_summary)
        else:
            lines.append("Анализ крашей не проводился.")
        lines.append("")

        # Раздел "Покрытие кода"
        lines.append("## Покрытие кода")
        lines.append("")
        if self.check_coverage_html():
            html_path = "coverage/html/index.html"
            lines.append(f"- [Отчёт покрытия (все режимы)]({html_path})")
            # Указываем для каких режимов есть данные
            covered_modes = [m for m in self.MODES if self.check_coverage_xml(m)]
            if covered_modes:
                lines.append(
                    f"- Данные собраны для режимов: {', '.join(covered_modes)}"
                )
        else:
            lines.append("Данные о покрытии отсутствуют.")
        lines.append("")

        # Раздел "Рекомендации"
        lines.append("## Рекомендации")
        lines.append("")
        has_coverage = self.check_coverage_html()
        recommendations = self.generate_recommendations(fuzzing_data, has_coverage)
        for rec in recommendations:
            lines.append(rec)
        lines.append("")

        return "\n".join(lines)

    def save_report(self, content: str) -> str:
        """Сохраняет отчёт в файл.

        :param content: содержимое отчёта
        :return: путь к сохранённому файлу
        """
        os.makedirs(self.results_dir, exist_ok=True)
        output_path = os.path.join(self.results_dir, "final_report.md")
        with open(output_path, "w", encoding="utf-8") as f:
            f.write(content)
        return output_path


def parse_args() -> argparse.Namespace:
    """Разбирает аргументы командной строки.

    :return: объект с разобранными аргументами
    """
    parser = argparse.ArgumentParser(
        description="Генерация сводного отчёта по результатам фаззинга"
    )
    parser.add_argument(
        "--project-root",
        required=True,
        help="Корневая директория проекта"
    )
    parser.add_argument(
        "--run-id",
        default=None,
        help="Идентификатор запуска (если не указан, читается из results/latest.txt)"
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    project_root = os.path.abspath(args.project_root)

    # Определяем RUN_ID
    if args.run_id:
        run_id = args.run_id.strip()
    else:
        latest_path = os.path.join(project_root, "results", "latest.txt")
        if os.path.isfile(latest_path):
            try:
                with open(latest_path, "r", encoding="utf-8") as f:
                    run_id = f.read().strip()
            except (OSError, IOError):
                print("ОШИБКА: Не удалось прочитать results/latest.txt.")
                sys.exit(1)
        else:
            print("ОШИБКА: Файл results/latest.txt не найден. Укажите --run-id.")
            sys.exit(1)

    if not run_id:
        print("ОШИБКА: Пустой RUN_ID.")
        sys.exit(1)

    # Генерируем отчёт
    generator = FuzzingReportGenerator(project_root, run_id)
    report_content = generator.generate_report()
    output_path = generator.save_report(report_content)

    # Выводим относительный путь от корня проекта
    relative_path = os.path.relpath(output_path, project_root)
    print(f"Отчёт сохранён: {relative_path}")
