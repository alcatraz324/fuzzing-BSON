# Fuzzing Newtonsoft.Json.Bson (AFL++ + SharpFuzz)

Coverage-guided фаззинг библиотеки Newtonsoft.Json.Bson 1.0.3:
три режима харнесса (reader / writer / differential), AFL++ fork server
через SharpFuzz, анализ крашей и покрытие кода через coverlet.

- Быстрый старт: `FUZZ_TIME_SECONDS=60 ./run_all.sh`
- Просмотр результатов: `./open_results.sh`
- Документация: `docs/README.md`, `docs/BASELINE.md`, `docs/FINDINGS.md`
- Базовая точка: тег `baseline-1`
