#!/bin/sh
set -eu

PROJECT_ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
BRIDGE_ROOT="$PROJECT_ROOT/SudachiBridge"
OUTPUT_ROOT="$PROJECT_ROOT/TablePOS/Frameworks/TablePOSSudachi.xcframework"
BUILD_ROOT="$PROJECT_ROOT/work/sudachi-build"

RUSTUP_HOME=${RUSTUP_HOME:-"$PROJECT_ROOT/work/rustup"}
CARGO_HOME=${CARGO_HOME:-"$PROJECT_ROOT/work/cargo"}
export RUSTUP_HOME CARGO_HOME
export PATH="$CARGO_HOME/bin:$PATH"
export CARGO_TARGET_DIR="$BUILD_ROOT/target"

if ! command -v cargo >/dev/null 2>&1; then
    echo "Rust is required. Install rustup or configure CARGO_HOME." >&2
    exit 1
fi

rustup target add aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios

cargo build --manifest-path "$BRIDGE_ROOT/Cargo.toml" --release --target aarch64-apple-ios
cargo build --manifest-path "$BRIDGE_ROOT/Cargo.toml" --release --target aarch64-apple-ios-sim
cargo build --manifest-path "$BRIDGE_ROOT/Cargo.toml" --release --target x86_64-apple-ios

mkdir -p "$BUILD_ROOT/device" "$BUILD_ROOT/simulator"
cp "$CARGO_TARGET_DIR/aarch64-apple-ios/release/libtablepos_sudachi.a" "$BUILD_ROOT/device/libTablePOSSudachi.a"
lipo -create \
    "$CARGO_TARGET_DIR/aarch64-apple-ios-sim/release/libtablepos_sudachi.a" \
    "$CARGO_TARGET_DIR/x86_64-apple-ios/release/libtablepos_sudachi.a" \
    -output "$BUILD_ROOT/simulator/libTablePOSSudachi.a"

if [ -d "$OUTPUT_ROOT" ]; then
    mv "$OUTPUT_ROOT" "$BUILD_ROOT/previous-xcframework-$(date +%s)"
fi

xcodebuild -create-xcframework \
    -library "$BUILD_ROOT/device/libTablePOSSudachi.a" -headers "$BRIDGE_ROOT/include" \
    -library "$BUILD_ROOT/simulator/libTablePOSSudachi.a" -headers "$BRIDGE_ROOT/include" \
    -output "$OUTPUT_ROOT"

echo "Created $OUTPUT_ROOT"
