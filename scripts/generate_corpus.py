#!/usr/bin/env python3
# scripts/generate_corpus.py
# Генератор начального корпуса валидных BSON-документов для фаззинга

"""Генерация seed-корпуса валидных BSON-документов различной структуры.

Корпус используется как начальный набор входных данных для фаззинга
библиотеки Newtonsoft.Json.Bson в трёх режимах:
  - reader: парсинг BSON из файла
  - writer: сериализация и перезапись
  - differential: сравнение reader → writer → reader

Формат BSON:
  Документ = [4 байта длина (little-endian int32)] + [элементы] + [0x00]
  Элемент  = [1 байт тип] + [ключ (cstring)] + [значение]
"""

import argparse
import os
import struct
from typing import List, Tuple


class BsonCorpusGenerator:
    """Генератор начального корпуса валидных BSON-документов для фаззинга."""

    # Режимы фаззинга, для которых создаётся корпус
    MODES: List[str] = ["reader", "writer", "differential"]

    def __init__(self, output_dir: str, count: int = 10) -> None:
        """Инициализация генератора.

        :param output_dir: корневая директория для записи корпуса
        :param count: количество документов на каждый режим (по умолчанию 10)
        """
        self.output_dir = output_dir
        self.count = count

    @staticmethod
    def _encode_cstring(s: str) -> bytes:
        """Кодирует строку как BSON cstring (UTF-8 + нулевой терминатор).

        :param s: входная строка
        :return: байтовое представление
        """
        return s.encode('utf-8') + b'\x00'

    @staticmethod
    def _encode_string(s: str) -> bytes:
        """Кодирует строку как BSON string (int32 длина + UTF-8 + null).

        :param s: входная строка
        :return: байтовое представление
        """
        encoded = s.encode('utf-8') + b'\x00'
        return struct.pack('<i', len(encoded)) + encoded

    @staticmethod
    def _encode_double(v: float) -> bytes:
        """Кодирует 8-байтное число с плавающей точкой (little-endian).

        :param v: значение
        :return: 8 байт
        """
        return struct.pack('<d', v)

    @staticmethod
    def _encode_int32(v: int) -> bytes:
        """Кодирует 32-битное целое (little-endian).

        :param v: значение
        :return: 4 байта
        """
        return struct.pack('<i', v)

    @staticmethod
    def _encode_int64(v: int) -> bytes:
        """Кодирует 64-битное целое (little-endian).

        :param v: значение
        :return: 8 байт
        """
        return struct.pack('<q', v)

    @classmethod
    def _encode_document(cls, elements: List[Tuple[int, str, bytes]]) -> bytes:
        """Собирает BSON-документ из списка элементов.

        :param elements: список кортежей (тип, ключ, значение)
        :return: полный BSON-документ
        """
        body = b''
        for type_byte, key, value in elements:
            body += bytes([type_byte]) + cls._encode_cstring(key) + value
        doc_body = body + b'\x00'
        return struct.pack('<i', len(doc_body) + 4) + doc_body

    def generate_documents(self) -> List[bytes]:
        """Генерирует набор валидных BSON-документов различной структуры.

        Если запрошено меньше 10 документов, возвращается срез первых
        запрошенных из базового набора. Если больше 10 — базовый набор
        повторяется по кругу с уникальными именами файлов.

        :return: список BSON-документов в байтовом виде
        """
        base_docs: List[bytes] = []

        # 1. Пустой документ {}
        base_docs.append(self._encode_document([]))

        # 2. Документ с одной строкой {"name": "test"}
        base_docs.append(self._encode_document([
            (0x02, "name", self._encode_string("test"))
        ]))

        # 3. Документ с числами разных типов
        base_docs.append(self._encode_document([
            (0x10, "i32", self._encode_int32(42)),
            (0x12, "i64", self._encode_int64(9876543210)),
            (0x01, "dbl", self._encode_double(3.14159)),
        ]))

        # 4. Документ с вложенным документом {"inner": {"key": "val"}}
        inner = self._encode_document([
            (0x02, "key", self._encode_string("val"))
        ])
        base_docs.append(self._encode_document([
            (0x03, "inner", inner)
        ]))

        # 5. Документ с массивом {"arr": [1, 2, 3]}
        arr = self._encode_document([
            (0x10, "0", self._encode_int32(1)),
            (0x10, "1", self._encode_int32(2)),
            (0x10, "2", self._encode_int32(3)),
        ])
        base_docs.append(self._encode_document([
            (0x04, "arr", arr)
        ]))

        # 6. Документ с булевым значением {"flag": true}
        base_docs.append(self._encode_document([
            (0x08, "flag", b'\x01')
        ]))

        # 7. Документ с null {"n": null}
        base_docs.append(self._encode_document([
            (0x0A, "n", b'')
        ]))

        # 8. Документ с датой {"dt": 2021-01-01T00:00:00Z}
        base_docs.append(self._encode_document([
            (0x09, "dt", self._encode_int64(1609459200000))
        ]))

        # 9. Документ с ObjectId {"_id": ...}
        base_docs.append(self._encode_document([
            (0x07, "_id", b'\x50\x7f\x1f\x77\xbc\xf8\x6c\xd7\x99\x43\x90\x11')
        ]))

        # 10. Документ с бинарными данными {"bin": ...}
        bin_data = b'\x01\x02\x03\x04\x05\x06\x07\x08'
        base_docs.append(self._encode_document([
            (0x05, "bin", struct.pack('<i', len(bin_data)) + b'\x00' + bin_data)
        ]))

        # Если запрошено больше 10, повторяем базовый набор по кругу
        if self.count <= len(base_docs):
            return base_docs[:self.count]

        docs: List[bytes] = []
        for i in range(self.count):
            docs.append(base_docs[i % len(base_docs)])
        return docs

    def write_corpus(self) -> Tuple[int, List[str]]:
        """Записывает сгенерированные документы в каталоги корпуса.

        Для каждого режима создаётся отдельный подкаталог, в который
        записываются все документы как отдельные файлы.

        :return: кортеж (количество документов, список режимов)
        """
        docs = self.generate_documents()

        for mode in self.MODES:
            mode_dir = os.path.join(self.output_dir, mode)
            os.makedirs(mode_dir, exist_ok=True)
            for i, doc in enumerate(docs, 1):
                filepath = os.path.join(mode_dir, f"seed_{i:04d}.bin")
                with open(filepath, 'wb') as f:
                    f.write(doc)

        return len(docs), self.MODES


def parse_args() -> argparse.Namespace:
    """Разбирает аргументы командной строки.

    :return: объект с разобранными аргументами
    """
    parser = argparse.ArgumentParser(
        description="Генератор начального корпуса валидных BSON-документов"
    )
    parser.add_argument(
        "--output-dir",
        required=True,
        help="Корневая директория для записи корпуса (например, build/corpus)"
    )
    parser.add_argument(
        "--count",
        type=int,
        default=10,
        help="Количество документов на каждый режим (по умолчанию: 10)"
    )
    return parser.parse_args()


if __name__ == "__main__":
    args = parse_args()
    generator = BsonCorpusGenerator(output_dir=args.output_dir, count=args.count)
    count, modes = generator.write_corpus()
    modes_str = ", ".join(modes)
    print(f"Сгенерировано {count} документов для каждого режима: {modes_str}")
