#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# Platform/compiler settings
# -----------------------------
if [[ "$(uname -s)" == "Darwin" ]]; then
  CC=${CC:-gcc-16}
  CXX=${CXX:-g++-16}
  FC=${FC:-gfortran-16}
else
  CC=${CC:-gcc}
  CXX=${CXX:-g++}
  FC=${FC:-gfortran}
fi

if [[ "$(uname -s)" == "Darwin" ]]; then
  CFLAGS=${CFLAGS:-"-O3 -mcpu=native -fPIC"}
  CXXFLAGS=${CXXFLAGS:-"-O3 -mcpu=native -fPIC"}
  FCFLAGS=${FCFLAGS:-"-O3 -mcpu=native -fPIC"}
else
  CFLAGS=${CFLAGS:-"-O3 -march=native -mtune=native -fPIC"}
  CXXFLAGS=${CXXFLAGS:-"-O3 -march=native -mtune=native -fPIC"}
  FCFLAGS=${FCFLAGS:-"-O3 -march=native -mtune=native -fPIC"}
fi

LDFLAGS=${LDFLAGS:-""}
if [[ "$(uname -s)" == "Darwin" ]]; then
  SDKROOT=${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}
  MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-15.0}
  export SDKROOT MACOSX_DEPLOYMENT_TARGET
  DARWIN_FLAGS="-isysroot ${SDKROOT} -mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET}"
  CFLAGS="${CFLAGS} ${DARWIN_FLAGS}"
  LDFLAGS="${LDFLAGS} ${DARWIN_FLAGS}"
fi
command -v "${CC}" >/dev/null

JOBS=${JOBS:-8}

# -----------------------------
# Project paths
# -----------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZIP_FILE="${SCRIPT_DIR}/gsl.zip"
OPT_DIR="${SCRIPT_DIR}/opt"
INSTALL_PREFIX="${OPT_DIR}/gsl"

# Set to 0 if you want to keep an existing installation and let "make install"
# overwrite files in place.
CLEAN_INSTALL_PREFIX=${CLEAN_INSTALL_PREFIX:-1}

BUILD_ROOT="${SCRIPT_DIR}/.build_gsl"

echo "==> Building GSL"
echo "    CC=${CC}"
echo "    CFLAGS=${CFLAGS}"
echo "    LDFLAGS=${LDFLAGS}"
echo "    INSTALL_PREFIX=${INSTALL_PREFIX}"

if [[ ! -f "${ZIP_FILE}" ]]; then
  echo "Error: ${ZIP_FILE} not found." >&2
  exit 1
fi

rm -rf "${BUILD_ROOT}"
mkdir -p "${BUILD_ROOT}" "${OPT_DIR}"

if [[ "${CLEAN_INSTALL_PREFIX}" == "1" ]]; then
  rm -rf "${INSTALL_PREFIX}"
fi

echo "==> Unzipping ${ZIP_FILE}"
unzip -q "${ZIP_FILE}" -d "${BUILD_ROOT}"

SRC_DIR="$(
  find "${BUILD_ROOT}" -mindepth 1 -maxdepth 3 -type f -name configure -print -quit |
  xargs dirname
)"

if [[ -z "${SRC_DIR}" || ! -x "${SRC_DIR}/configure" ]]; then
  echo "Error: could not find an executable configure script after unzipping ${ZIP_FILE}." >&2
  exit 1
fi

echo "==> Source directory: ${SRC_DIR}"
cd "${SRC_DIR}"

echo "==> Configuring"
./configure \
  --prefix="${INSTALL_PREFIX}" \
  CC="${CC}" \
  CFLAGS="${CFLAGS}" \
  LDFLAGS="${LDFLAGS}"

echo "==> Compiling with ${JOBS} jobs"
make -j"${JOBS}"

echo "==> Installing"
make install

echo "==> Verifying installation"
"${INSTALL_PREFIX}/bin/gsl-config" --version
"${INSTALL_PREFIX}/bin/gsl-config" --libs

echo "==> Cleaning extracted source"
cd "${SCRIPT_DIR}"
rm -rf "${BUILD_ROOT}"

echo "==> Done. GSL installed at ${INSTALL_PREFIX}"
