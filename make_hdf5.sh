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
  CXXFLAGS="${CXXFLAGS} ${DARWIN_FLAGS}"
  FCFLAGS="${FCFLAGS} ${DARWIN_FLAGS}"
  LDFLAGS="${LDFLAGS} ${DARWIN_FLAGS}"
fi
command -v "${CC}" >/dev/null
command -v "${CXX}" >/dev/null
command -v "${FC}" >/dev/null

JOBS=${JOBS:-8}

# Build serial HDF5. NuHamil only needs the Fortran HDF5 API for file I/O, not
# parallel HDF5, so serial HDF5 avoids MPI library mixing issues.
ENABLE_FORTRAN=yes
ENABLE_SHARED=yes
ENABLE_PARALLEL=no

# -----------------------------
# Project paths
# -----------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZIP_FILE="${SCRIPT_DIR}/hdf5.zip"
OPT_DIR="${SCRIPT_DIR}/opt"
INSTALL_PREFIX="${OPT_DIR}/hdf5"

BUILD_ROOT="${SCRIPT_DIR}/.build_hdf5"

echo "==> Building HDF5"
echo "    CC=${CC}"
echo "    CXX=${CXX}"
echo "    FC=${FC}"
echo "    CFLAGS=${CFLAGS}"
echo "    CXXFLAGS=${CXXFLAGS}"
echo "    FCFLAGS=${FCFLAGS}"
echo "    LDFLAGS=${LDFLAGS}"
echo "    ENABLE_FORTRAN=${ENABLE_FORTRAN}"
echo "    ENABLE_SHARED=${ENABLE_SHARED}"
echo "    ENABLE_PARALLEL=${ENABLE_PARALLEL}"
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
  find "${BUILD_ROOT}" -mindepth 1 -maxdepth 4 -type f -path '*/src/H5.c' -print -quit |
  sed 's#/src/H5.c$##'
)"

if [[ -z "${SRC_DIR}" || ! -x "${SRC_DIR}/configure" || ! -f "${SRC_DIR}/fortran/src/H5f90global.F90" ]]; then
  echo "Error: could not find HDF5 top-level source directory after unzipping ${ZIP_FILE}." >&2
  exit 1
fi

echo "==> Source directory: ${SRC_DIR}"
cd "${SRC_DIR}"

echo "==> Configuring"
./configure \
  --prefix="${INSTALL_PREFIX}" \
  CC="${CC}" \
  CXX="${CXX}" \
  FC="${FC}" \
  CFLAGS="${CFLAGS}" \
  CXXFLAGS="${CXXFLAGS}" \
  FCFLAGS="${FCFLAGS}" \
  LDFLAGS="${LDFLAGS}" \
  --enable-fortran="${ENABLE_FORTRAN}" \
  --enable-shared="${ENABLE_SHARED}" \
  --enable-parallel="${ENABLE_PARALLEL}"

echo "==> Compiling with ${JOBS} jobs"
make -j"${JOBS}"

echo "==> Installing"
make install

echo "==> Verifying installation"
find "${INSTALL_PREFIX}" -name hdf5.mod -print
find "${INSTALL_PREFIX}" -name 'libhdf5_fortran*' -print
if [[ "${ENABLE_FORTRAN}" == "yes" ]]; then
  "${INSTALL_PREFIX}/bin/h5fc" -show
fi

echo "==> Cleaning extracted source"
cd "${SCRIPT_DIR}"
rm -rf "${BUILD_ROOT}"

echo "==> Done. HDF5 installed at ${INSTALL_PREFIX}"
