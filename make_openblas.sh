#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# Platform/compiler settings
# -----------------------------
if [[ "$(uname -s)" == "Darwin" ]]; then
  CC=${CC:-gcc-16}
  FC=${FC:-gfortran-16}
else
  CC=${CC:-gcc}
  FC=${FC:-gfortran}
fi

CFLAGS=${CFLAGS:-"-O3 -fPIC"}
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
command -v "${FC}" >/dev/null

JOBS=${JOBS:-8}

# Build OpenMP-threaded OpenBLAS; control runtime threads with OMP_NUM_THREADS.
USE_THREAD=1
USE_OPENMP=1
NO_AFFINITY=1
DYNAMIC_ARCH=1

# -----------------------------
# Project paths
# -----------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZIP_FILE="${SCRIPT_DIR}/openblas.zip"
OPT_DIR="${SCRIPT_DIR}/opt"
INSTALL_PREFIX="${OPT_DIR}/openblas"

BUILD_ROOT="${SCRIPT_DIR}/.build_openblas"

echo "==> Building OpenBLAS"
echo "    CC=${CC}"
echo "    FC=${FC}"
echo "    CFLAGS=${CFLAGS}"
echo "    FFLAGS=${FFLAGS}"
echo "    LDFLAGS=${LDFLAGS}"
echo "    USE_THREAD=${USE_THREAD}"
echo "    USE_OPENMP=${USE_OPENMP}"
echo "    DYNAMIC_ARCH=${DYNAMIC_ARCH}"
echo "    INSTALL_PREFIX=${INSTALL_PREFIX}"

if [[ ! -f "${ZIP_FILE}" ]]; then
  echo "Error: ${ZIP_FILE} not found." >&2
  exit 1
fi

rm -rf "${BUILD_ROOT}" "${INSTALL_PREFIX}"
mkdir -p "${BUILD_ROOT}" "${OPT_DIR}"

echo "==> Unzipping ${ZIP_FILE}"
unzip -q "${ZIP_FILE}" -d "${BUILD_ROOT}"

SRC_DIR="$(
  find "${BUILD_ROOT}" -mindepth 1 -maxdepth 3 -type f -name Makefile.system -print -quit |
  xargs dirname
)"

if [[ -z "${SRC_DIR}" || ! -f "${SRC_DIR}/Makefile" || ! -f "${SRC_DIR}/Makefile.install" ]]; then
  echo "Error: could not find OpenBLAS top-level Makefile after unzipping ${ZIP_FILE}." >&2
  exit 1
fi

echo "==> Source directory: ${SRC_DIR}"
cd "${SRC_DIR}"

MAKE_ARGS=(
  CC="${CC}"
  FC="${FC}"
  CFLAGS="${CFLAGS}"
  FFLAGS="${FFLAGS}"
  LDFLAGS="${LDFLAGS}"
  USE_THREAD="${USE_THREAD}"
  USE_OPENMP="${USE_OPENMP}"
  NO_AFFINITY="${NO_AFFINITY}"
  DYNAMIC_ARCH="${DYNAMIC_ARCH}"
)

echo "==> Compiling with ${JOBS} jobs"
make -j"${JOBS}" "${MAKE_ARGS[@]}"

echo "==> Installing"
make install PREFIX="${INSTALL_PREFIX}" "${MAKE_ARGS[@]}"

echo "==> Verifying installation"
ls "${INSTALL_PREFIX}/lib"/libopenblas.*
if [[ -x "${INSTALL_PREFIX}/bin/openblas_get_config" ]]; then
  "${INSTALL_PREFIX}/bin/openblas_get_config"
fi

echo "==> Cleaning extracted source"
cd "${SCRIPT_DIR}"
rm -rf "${BUILD_ROOT}"

echo "==> Done. OpenBLAS installed at ${INSTALL_PREFIX}"
