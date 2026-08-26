#!/bin/sh
set -eu

VERSION="20260723"
EXPECTED_SHA256="b3869ce6b12b4bfa09575dc19030703bb669ab41bac12a74cafcbb28c6be2498"
EXPECTED_DICTIONARY_SHA256="53fa281d11eef3769712fe1c3c892117338f9892bee6daf4dad51daa5281bb6f"
WHEEL_NAME="sudachidict_core-${VERSION}-py3-none-any.whl"
DOWNLOAD_URL="https://github.com/WorksApplications/SudachiDict/releases/download/v${VERSION}/${WHEEL_NAME}"

PROJECT_ROOT=${PROJECT_DIR:-$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)}
RESOURCE_BUNDLE="$PROJECT_ROOT/TablePOS/Resources/SudachiResources.bundle"
DESTINATION="$RESOURCE_BUNDLE/system.dic"
CACHE_ROOT="${DERIVED_FILE_DIR:-$PROJECT_ROOT/work/sudachi-dictionary}"
WHEEL="$CACHE_ROOT/$WHEEL_NAME"
UNPACKED="$CACHE_ROOT/unpacked-$VERSION"

if [ -s "$DESTINATION" ]; then
    ACTUAL_DICTIONARY_SHA256=$(shasum -a 256 "$DESTINATION" | awk '{print $1}')
    if [ "$ACTUAL_DICTIONARY_SHA256" = "$EXPECTED_DICTIONARY_SHA256" ]; then
        exit 0
    fi
    echo "Existing Sudachi dictionary checksum mismatch; replacing it." >&2
    rm -f "$DESTINATION"
fi

mkdir -p "$CACHE_ROOT" "$RESOURCE_BUNDLE"

if [ ! -s "$WHEEL" ]; then
    echo "Downloading SudachiDict core ${VERSION}…"
    curl --fail --location --retry 3 --output "$WHEEL" "$DOWNLOAD_URL"
fi

ACTUAL_SHA256=$(shasum -a 256 "$WHEEL" | awk '{print $1}')
if [ "$ACTUAL_SHA256" != "$EXPECTED_SHA256" ]; then
    echo "SudachiDict checksum mismatch." >&2
    exit 1
fi

mkdir -p "$UNPACKED"
ditto -x -k "$WHEEL" "$UNPACKED"
SOURCE="$UNPACKED/sudachidict_core/resources/system.dic"
if [ ! -s "$SOURCE" ]; then
    echo "SudachiDict archive did not contain system.dic." >&2
    exit 1
fi

cp "$SOURCE" "$DESTINATION"
ACTUAL_DICTIONARY_SHA256=$(shasum -a 256 "$DESTINATION" | awk '{print $1}')
if [ "$ACTUAL_DICTIONARY_SHA256" != "$EXPECTED_DICTIONARY_SHA256" ]; then
    rm -f "$DESTINATION"
    echo "Extracted Sudachi dictionary checksum mismatch." >&2
    exit 1
fi
echo "Installed SudachiDict core at $DESTINATION"
