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
# Keep the B2 toolset and its compiler registration on the same version.
GCC_VERSION=$("${CXX}" -dumpversion)
GCC_VERSION=${GCC_VERSION%%.*}
TOOLSET=${TOOLSET:-gcc-${GCC_VERSION}}

if [[ "$(uname -s)" == "Darwin" ]]; then
  CFLAGS=${CFLAGS:-"-O3 -mcpu=native -fPIC"}
  CXXFLAGS=${CXXFLAGS:-"-O3 -mcpu=native -fPIC"}
else
  CFLAGS=${CFLAGS:-"-O3 -march=native -mtune=native -fPIC"}
  CXXFLAGS=${CXXFLAGS:-"-O3 -march=native -mtune=native -fPIC"}
fi
LINKFLAGS=${LINKFLAGS:-""}

if [[ "$(uname -s)" == "Darwin" ]]; then
  # GCC's configured SDK can disappear after a Command Line Tools update.
  SDKROOT=${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}
  MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-15.0}
  export SDKROOT MACOSX_DEPLOYMENT_TARGET
  DARWIN_FLAGS="-isysroot ${SDKROOT} -mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET}"
  CFLAGS="${CFLAGS} ${DARWIN_FLAGS}"
  CXXFLAGS="${CXXFLAGS} ${DARWIN_FLAGS}"
  LINKFLAGS="${LINKFLAGS} ${DARWIN_FLAGS}"
fi

export CC CXX FC

JOBS=8

# Build as much Boost as is practical for a portable scientific stack.
# Boost.Python is disabled by default because it often needs matching Python
# development headers and libraries. Set BUILD_PYTHON=yes and configure the
# Python variables below if you need it.
BUILD_PYTHON=no
PYTHON_BIN=python3
PYTHON_INCLUDE=
PYTHON_LIB_PATH=

# Boost.MPI is enabled automatically when this OpenMPI installation exists.
ENABLE_MPI=yes

# -----------------------------
# Project paths
# -----------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZIP_FILE="${SCRIPT_DIR}/boost.zip"
OPT_DIR="${SCRIPT_DIR}/opt"
INSTALL_PREFIX="${OPT_DIR}/boost"
MPI_ROOT="${OPT_DIR}/openmpi"

BUILD_ROOT="${SCRIPT_DIR}/.build_boost"

echo "==> Building Boost"
echo "    CC=${CC}"
echo "    CXX=${CXX}"
echo "    TOOLSET=${TOOLSET}"
echo "    CFLAGS=${CFLAGS}"
echo "    CXXFLAGS=${CXXFLAGS}"
echo "    LINKFLAGS=${LINKFLAGS}"
echo "    BUILD_PYTHON=${BUILD_PYTHON}"
echo "    ENABLE_MPI=${ENABLE_MPI}"
echo "    MPI_ROOT=${MPI_ROOT}"
echo "    INSTALL_PREFIX=${INSTALL_PREFIX}"

if [[ ! -f "${ZIP_FILE}" ]]; then
  echo "Error: ${ZIP_FILE} not found." >&2
  exit 1
fi

# Check the compiler and SDK before removing an existing installation.
PROBE_DIR=$(mktemp -d "${TMPDIR:-/tmp}/boost-compiler.XXXXXX")
trap 'rm -rf "${PROBE_DIR}"' EXIT
if ! printf '#include <iostream>\nint main(){std::cout << "Compiler OK\\n";}\n' |
  "${CXX}" ${CXXFLAGS} -x c++ - ${LINKFLAGS} -o "${PROBE_DIR}/probe"; then
  echo "Error: C++ compiler/SDK check failed; existing installation preserved." >&2
  exit 1
fi
"${PROBE_DIR}/probe"

rm -rf "${BUILD_ROOT}" "${INSTALL_PREFIX}"
mkdir -p "${BUILD_ROOT}" "${OPT_DIR}"

echo "==> Unzipping ${ZIP_FILE}"
if [[ "$(uname -s)" == "Darwin" ]]; then
  # Apple's unzip can fail on Boost.Wave test paths that intentionally contain
  # unusual UTF-8 names. bsdtar handles the archive metadata more reliably.
  bsdtar -xf "${ZIP_FILE}" -C "${BUILD_ROOT}"
else
  unzip -q "${ZIP_FILE}" -d "${BUILD_ROOT}"
fi

SRC_DIR="$(
  find "${BUILD_ROOT}" -mindepth 2 -maxdepth 4 -type f -path '*/boost/version.hpp' -print -quit |
  sed 's#/boost/version.hpp$##'
)"

if [[ -z "${SRC_DIR}" || ! -f "${SRC_DIR}/bootstrap.sh" ]]; then
  echo "Error: could not find Boost top-level source directory after unzipping ${ZIP_FILE}." >&2
  exit 1
fi

echo "==> Source directory: ${SRC_DIR}"
cd "${SRC_DIR}"
chmod +x bootstrap.sh
chmod +x tools/build/src/engine/build.sh

if [[ ! -f "boost/version.hpp" || ! -f "tools/build/src/engine/build.sh" ]]; then
  cat >&2 <<EOF
Error: ${ZIP_FILE} does not look like a complete Boost release archive.

The archive has bootstrap.sh, but required files are missing, for example:
  boost/version.hpp
  tools/build/src/engine/build.sh

This usually means boost.zip is a GitHub superproject snapshot without
submodules. Use an official Boost release archive instead, e.g.
boost_1_85_0.zip / boost_1_85_0.tar.gz or newer, then rename it to boost.zip.
EOF
  exit 1
fi

BOOTSTRAP_ARGS=(
  "--prefix=${INSTALL_PREFIX}"
  "--with-toolset=gcc"
)

if [[ "${BUILD_PYTHON}" == "yes" ]]; then
  BOOTSTRAP_ARGS+=("--with-python=${PYTHON_BIN}")
fi

echo "==> Bootstrapping"
./bootstrap.sh "${BOOTSTRAP_ARGS[@]}"

cat >> project-config.jam <<EOF

using gcc : ${GCC_VERSION} : ${CXX} : <cxxflags>"${CXXFLAGS}" <linkflags>"${LINKFLAGS}" ;
EOF

if [[ "${ENABLE_MPI}" == "yes" && -x "${MPI_ROOT}/bin/mpic++" ]]; then
  cat >> project-config.jam <<EOF

using mpi : ${MPI_ROOT}/bin/mpic++ ;
EOF
  export PATH="${MPI_ROOT}/bin:${PATH}"
  export LD_LIBRARY_PATH="${MPI_ROOT}/lib:${LD_LIBRARY_PATH:-}"
  echo "==> Boost.MPI enabled with ${MPI_ROOT}/bin/mpic++"
else
  echo "==> Boost.MPI not enabled; ${MPI_ROOT}/bin/mpic++ was not found or ENABLE_MPI is not yes."
  ENABLE_MPI=no
fi

if [[ "${BUILD_PYTHON}" == "yes" && -n "${PYTHON_INCLUDE}" && -n "${PYTHON_LIB_PATH}" ]]; then
  cat >> project-config.jam <<EOF

using python : : ${PYTHON_BIN} : ${PYTHON_INCLUDE} : ${PYTHON_LIB_PATH} ;
EOF
fi

B2_ARGS=(
  "-j${JOBS}"
  "install"
  "--prefix=${INSTALL_PREFIX}"
  "--layout=system"
  "toolset=${TOOLSET}"
  "variant=release"
  "threading=multi"
  "link=shared,static"
  "runtime-link=shared"
  "cflags=${CFLAGS}"
  "cxxflags=${CXXFLAGS}"
  "linkflags=${LINKFLAGS}"
  "-sNO_BZIP2=1"
)

if [[ "${BUILD_PYTHON}" != "yes" ]]; then
  B2_ARGS+=("--without-python")
fi

if [[ "${ENABLE_MPI}" != "yes" ]]; then
  B2_ARGS+=("--without-mpi" "--without-graph_parallel")
fi

if [[ "$(uname -s)" == "Darwin" && "${TOOLSET}" == gcc-* ]]; then
  # Boost.Context 1.91 does not select a Mach-O ARM64 assembler source for the
  # versioned GNU toolset here, which also breaks libraries layered on it.
  B2_ARGS+=(
    "--without-context"
    "--without-coroutine"
    "--without-fiber"
    "--without-cobalt"
    "--without-process"
  )
fi

echo "==> Compiling and installing with ${JOBS} jobs"
./b2 "${B2_ARGS[@]}"

echo "==> Verifying installation"
find "${INSTALL_PREFIX}/include" -maxdepth 2 -type f -name version.hpp -print
find "${INSTALL_PREFIX}/lib" -maxdepth 1 -type f \( -name 'libboost_*.so' -o -name 'libboost_*.a' -o -name 'libboost_*.dylib' \) | sort | head -40
echo "==> Number of Boost libraries installed:"
find "${INSTALL_PREFIX}/lib" -maxdepth 1 -type f \( -name 'libboost_*.so' -o -name 'libboost_*.a' -o -name 'libboost_*.dylib' \) | wc -l

echo "==> Cleaning extracted source"
cd "${SCRIPT_DIR}"
rm -rf "${BUILD_ROOT}"

echo "==> Done. Boost installed at ${INSTALL_PREFIX}"
