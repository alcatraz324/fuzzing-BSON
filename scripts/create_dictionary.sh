#!/usr/bin/env bash
# scripts/create_dictionary.sh
set -euo pipefail
cd "$(dirname "$0")/.."
source config/project.env

echo "=== Создание BSON-словаря для AFL++ ==="
mkdir -p "$PROJECT_ROOT/build"

cat > "$PROJECT_ROOT/build/bson.dict" << 'DICT_EOF'
# Словарь токенов BSON для AFL++
# Формат AFL++: keyword="value" (hex задаётся через \xNN внутри кавычек)

bson_type_double="\x01"
bson_type_string="\x02"
bson_type_document="\x03"
bson_type_array="\x04"
bson_type_binary="\x05"
bson_type_undefined="\x06"
bson_type_objectid="\x07"
bson_type_boolean="\x08"
bson_type_datetime="\x09"
bson_type_null="\x0a"
bson_type_regex="\x0b"
bson_type_dbpointer="\x0c"
bson_type_javascript="\x0d"
bson_type_symbol="\x0e"
bson_type_javascript_scope="\x0f"
bson_type_int32="\x10"
bson_type_timestamp="\x11"
bson_type_int64="\x12"
bson_type_decimal128="\x13"
bson_type_minkey="\xff"
bson_type_maxkey="\x7f"

bson_null_terminator="\x00"

bson_key_id="_id"
bson_key_name="name"
bson_key_value="value"
bson_key_type="type"
bson_key_data="data"
bson_key_index="index"
bson_key_key="key"
bson_key_item="item"

bson_int32_one="\x01\x00\x00\x00"
bson_int32_minus_one="\xff\xff\xff\xff"
bson_int32_zero="\x00\x00\x00\x00"
bson_int32_max="\xfe\xff\xff\x7f"

bson_empty_doc_size="\x05\x00\x00\x00"

bson_bool_false="\x00"
bson_bool_true="\x01"

bson_objectid_zero="\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00\x00"

bson_binary_generic="\x00"
bson_binary_function="\x01"
bson_binary_uuid="\x04"
bson_binary_md5="\x05"
bson_binary_encrypted="\x06"
bson_binary_user_defined="\x80"
DICT_EOF

echo "  Словарь создан: build/bson.dict ($(wc -c < "$PROJECT_ROOT/build/bson.dict") байт)"
echo "=== Создание словаря завершено ==="
