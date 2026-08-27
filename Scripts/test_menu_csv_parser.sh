#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
OUTPUT_DIR="$PROJECT_ROOT/work/csv-parser-tests"
EXECUTABLE="$OUTPUT_DIR/menu-csv-parser-tests"

mkdir -p "$OUTPUT_DIR"

xcrun swiftc \
    "$PROJECT_ROOT/TablePOS/Models/Enums.swift" \
    "$PROJECT_ROOT/TablePOS/Services/MenuCSVImportService.swift" \
    "$PROJECT_ROOT/Tests/MenuCSVParser/main.swift" \
    -o "$EXECUTABLE"

cd "$PROJECT_ROOT"
"$EXECUTABLE"
