#!/usr/bin/env bash
# ==============================================================================
# compile_shims.sh — Build iOS Compatibility Shims for Stray iOS Port
# ==============================================================================
# Target: iOS 17.0+ (ARM64)
# Requires: Xcode command line tools with iphoneos SDK
# ==============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
SHIMS_DIR="${REPO_ROOT}/source/shims"
OUTPUT_DIR="${1:-${REPO_ROOT}/build/shims}"

echo "===================================================================="
echo " Stray iOS — Compatibility Shims Compiler"
echo "===================================================================="
echo "Source Directory : ${SHIMS_DIR}"
echo "Output Directory : ${OUTPUT_DIR}"

mkdir -p "${OUTPUT_DIR}"

SDK="iphoneos"
TARGET="arm64-apple-ios17.0"
ARCH="arm64"
OPT_FLAGS="-O2 -fobjc-arc -Wno-incompatible-library-redeclaration -Wno-deprecated-declarations"

echo "[1/5] Compiling libShim_AppKit.dylib..."
xcrun -sdk "${SDK}" clang \
    -target "${TARGET}" \
    -arch "${ARCH}" \
    -dynamiclib \
    -install_name @rpath/libShim_AppKit.dylib \
    ${OPT_FLAGS} \
    -framework Foundation \
    -framework UIKit \
    -framework QuartzCore \
    -framework CoreGraphics \
    -framework Metal \
    -framework GameController \
    -Wl,-reexport_framework,UIKit \
    "${SHIMS_DIR}/AppKit.m" \
    "${SHIMS_DIR}/AppKit_RuntimeHooks.m" \
    -o "${OUTPUT_DIR}/libShim_AppKit.dylib"

echo "[2/5] Compiling libShim_IOKit.dylib..."
xcrun -sdk "${SDK}" clang \
    -target "${TARGET}" \
    -arch "${ARCH}" \
    -dynamiclib \
    -install_name @rpath/libShim_IOKit.dylib \
    ${OPT_FLAGS} \
    -framework Foundation \
    -framework Metal \
    "${SHIMS_DIR}/IOKit.m" \
    -o "${OUTPUT_DIR}/libShim_IOKit.dylib"

echo "[3/5] Compiling libShim_libSystem.dylib..."
xcrun -sdk "${SDK}" clang \
    -target "${TARGET}" \
    -arch "${ARCH}" \
    -dynamiclib \
    -install_name @rpath/libShim_libSystem.dylib \
    -O2 -fobjc-arc -Wno-incompatible-library-redeclaration -Wno-deprecated-declarations -Wno-invalid-noreturn \
    -framework Foundation \
    -lpthread \
    "${SHIMS_DIR}/libSystem.m" \
    -o "${OUTPUT_DIR}/libShim_libSystem.dylib"

echo "[4/5] Compiling libShim_CoreGraphics.dylib..."
xcrun -sdk "${SDK}" clang \
    -target "${TARGET}" \
    -arch "${ARCH}" \
    -dynamiclib \
    -install_name @rpath/libShim_CoreGraphics.dylib \
    ${OPT_FLAGS} \
    -framework Foundation \
    -framework CoreGraphics \
    -framework UIKit \
    -framework Metal \
    "${SHIMS_DIR}/CoreGraphics.m" \
    -o "${OUTPUT_DIR}/libShim_CoreGraphics.dylib"

echo "[5/5] Compiling libShim_Metal.dylib..."
xcrun -sdk "${SDK}" clang \
    -target "${TARGET}" \
    -arch "${ARCH}" \
    -dynamiclib \
    -install_name @rpath/libShim_Metal.dylib \
    ${OPT_FLAGS} \
    -framework Foundation \
    -framework Metal \
    "${SHIMS_DIR}/Metal.m" \
    -o "${OUTPUT_DIR}/libShim_Metal.dylib"

echo "===================================================================="
echo " Verifying Generated Dynamic Libraries"
echo "===================================================================="

for dylib in "${OUTPUT_DIR}"/*.dylib; do
    fname="$(basename "${dylib}")"
    echo -n "Checking ${fname}... "
    # Verify Mach-O ARM64
    file_info="$(file -b "${dylib}")"
    if [[ "${file_info}" != *"Mach-O 64-bit dynamically linked shared library arm64"* ]]; then
        echo "FAILED (Unexpected binary format: ${file_info})"
        exit 1
    fi
    # Verify build platform
    platform_info="$(xcrun vtool -show-build "${dylib}" | grep -E "platform (IOS|7)" || true)"
    if [[ -z "${platform_info}" ]]; then
        echo "FAILED (Missing iOS platform load command)"
        exit 1
    fi
    size="$(stat -f%z "${dylib}")"
    echo "OK (${size} bytes)"
done

echo "===================================================================="
echo " All shims compiled and verified successfully in: ${OUTPUT_DIR}"
echo "===================================================================="
