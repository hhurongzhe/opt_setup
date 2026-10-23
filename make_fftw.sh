#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# Platform/compiler settings
# -----------------------------
if [[ "$(uname -s)" == "Darwin" ]]; then
  CC=${CC:-gcc-16}
  F77=${F77:-gfortran-16}
else
  CC=${CC:-gcc}
  F77=${F77:-gfortran}
fi

if [[ "$(uname -s)" == "Darwin" ]]; then
  CFLAGS=${CFLAGS:-"-O3 -mcpu=native -fPIC"}
else
  CFLAGS=${CFLAGS:-"-O3 -march=native -mtune=native -fPIC"}
fi

FFLAGS=${FFLAGS:-"-O3 -fPIC"}
LDFLAGS=${LDFLAGS:-""}
if [[ "$(uname -s)" == "Darwin" ]]; then
  SDKROOT=${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}
  MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-15.0}
  export SDKROOT MACOSX_DEPLOYMENT_TARGET
  DARWIN_FLAGS="-isysroot ${SDKROOT} -mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET}"
  CFLAGS="${CFLAGS} ${DARWIN_FLAGS}"
  FFLAGS="${FFLAGS} ${DARWIN_FLAGS}"
  LDFLAGS="${LDFLAGS} ${DARWIN_FLAGS}"
fi
command -v "${CC}" >/dev/null
command -v "${F77}" >/dev/null

JOBS=${JOBS:-8}

# -----------------------------
# Project paths
# -----------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ARCHIVE_FILE="${SCRIPT_DIR}/fftw-3.3.11.tar.gz"
OPT_DIR="${SCRIPT_DIR}/opt"
INSTALL_PREFIX="${OPT_DIR}/fftw"
BUILD_ROOT="${SCRIPT_DIR}/.build_fftw"

# Set to 0 to keep an existing installation and overwrite it in place.
CLEAN_INSTALL_PREFIX=${CLEAN_INSTALL_PREFIX:-1}

echo "==> Building FFTW"
echo "    CC=${CC}"
echo "    F77=${F77}"
echo "    CFLAGS=${CFLAGS}"
echo "    FFLAGS=${FFLAGS}"
echo "    LDFLAGS=${LDFLAGS}"
echo "    JOBS=${JOBS}"
echo "    INSTALL_PREFIX=${INSTALL_PREFIX}"

if [[ ! -f "${ARCHIVE_FILE}" ]]; then
  echo "Error: ${ARCHIVE_FILE} not found." >&2
  exit 1
fi

rm -rf "${BUILD_ROOT}"
mkdir -p "${BUILD_ROOT}" "${OPT_DIR}"

if [[ "${CLEAN_INSTALL_PREFIX}" == "1" ]]; then
  rm -rf "${INSTALL_PREFIX}"
fi

echo "==> Extracting ${ARCHIVE_FILE}"
tar -xzf "${ARCHIVE_FILE}" -C "${BUILD_ROOT}"

SRC_DIR="$(
  find "${BUILD_ROOT}" -mindepth 1 -maxdepth 2 -type f -name configure -print -quit |
    xargs dirname
)"

if [[ -z "${SRC_DIR}" || ! -x "${SRC_DIR}/configure" ]]; then
  echo "Error: could not find an executable FFTW configure script." >&2
  exit 1
fi

# Enable only SIMD instruction sets accepted by the selected compiler and
# native CPU. FFTW selects the appropriate codelet at runtime.
COMPILER_DEFINES="$(printf '' | "${CC}" ${CFLAGS} -dM -E - 2>/dev/null || true)"
SIMD_ARGS=()
if grep -q '__ARM_NEON' <<<"${COMPILER_DEFINES}"; then
  SIMD_ARGS+=(--enable-neon)
fi
if grep -q '__SSE2__' <<<"${COMPILER_DEFINES}"; then
  SIMD_ARGS+=(--enable-sse2)
fi
if grep -q '__AVX__' <<<"${COMPILER_DEFINES}"; then
  SIMD_ARGS+=(--enable-avx)
fi
if grep -q '__AVX2__' <<<"${COMPILER_DEFINES}"; then
  SIMD_ARGS+=(--enable-avx2)
fi

echo "==> Source directory: ${SRC_DIR}"
echo "    SIMD options: ${SIMD_ARGS[*]:-none}"
cd "${SRC_DIR}"

echo "==> Configuring"
./configure \
  --prefix="${INSTALL_PREFIX}" \
  --enable-shared \
  --disable-static \
  --enable-threads \
  "${SIMD_ARGS[@]}" \
  CC="${CC}" \
  F77="${F77}" \
  CFLAGS="${CFLAGS}" \
  FFLAGS="${FFLAGS}" \
  LDFLAGS="${LDFLAGS}"

echo "==> Compiling with ${JOBS} jobs"
make -j"${JOBS}"

echo "==> Running FFTW test suite"
make check -j"${JOBS}"

echo "==> Installing"
make install

echo "==> Verifying installation"
test -f "${INSTALL_PREFIX}/include/fftw3.h"
test -n "$(find "${INSTALL_PREFIX}/lib" -maxdepth 1 -name 'libfftw3.*' -print -quit)"
test -n "$(find "${INSTALL_PREFIX}/lib" -maxdepth 1 -name 'libfftw3_threads.*' -print -quit)"
"${INSTALL_PREFIX}/bin/fftw-wisdom" --version

echo "==> Cleaning extracted source"
cd "${SCRIPT_DIR}"
rm -rf "${BUILD_ROOT}"

echo "==> Done. FFTW installed at ${INSTALL_PREFIX}"
