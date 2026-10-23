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

LDFLAGS=${LDFLAGS:-""}

if [[ "$(uname -s)" == "Darwin" ]]; then
  CFLAGS=${CFLAGS:-"-O3 -mcpu=native -fPIC"}
  CXXFLAGS=${CXXFLAGS:-"-O3 -mcpu=native -fPIC"}
  FCFLAGS=${FCFLAGS:-"-O3 -mcpu=native -fPIC"}
  # Resolve the active SDK instead of relying on GCC's build-time SDK path.
  SDKROOT=${SDKROOT:-$(xcrun --sdk macosx --show-sdk-path)}
  MACOSX_DEPLOYMENT_TARGET=${MACOSX_DEPLOYMENT_TARGET:-15.0}
  export SDKROOT MACOSX_DEPLOYMENT_TARGET
  DARWIN_FLAGS="-isysroot ${SDKROOT} -mmacosx-version-min=${MACOSX_DEPLOYMENT_TARGET}"
  CFLAGS="${CFLAGS} ${DARWIN_FLAGS}"
  CXXFLAGS="${CXXFLAGS} ${DARWIN_FLAGS}"
  FCFLAGS="${FCFLAGS} ${DARWIN_FLAGS}"
  LDFLAGS="${LDFLAGS} ${DARWIN_FLAGS}"
  # Libtool queries kern.argmax with sysctl on Darwin. In sandboxed shells this
  # can fail and leave max_cmd_len empty, which breaks large library links.
  export lt_cv_sys_max_cmd_len="${lt_cv_sys_max_cmd_len:-262144}"
else
  CFLAGS=${CFLAGS:-"-O3 -march=native -mtune=native -fPIC"}
  CXXFLAGS=${CXXFLAGS:-"-O3 -march=native -mtune=native -fPIC"}
  FCFLAGS=${FCFLAGS:-"-O3 -march=native -mtune=native -fPIC"}
fi

JOBS=8

# OpenMPI build options. This is a fuller generic build while still keeping the
# dependency stack self-contained.
ENABLE_MPI_FORTRAN=yes
ENABLE_OSHMEM=no
ENABLE_SHARED=yes
ENABLE_STATIC=no
ENABLE_MPI_JAVA=no
ENABLE_IPV6=yes
ENABLE_WRAPPER_RPATH=yes
ENABLE_WRAPPER_RUNPATH=yes
ENABLE_MPIRUN_PREFIX_BY_DEFAULT=yes

# Prefer bundled third-party dependencies to avoid mixing incompatible system
# libraries. If your OpenMPI source release does not provide one of these, the
# configure step will report it clearly.
WITH_HWLOC=internal
WITH_LIBEVENT=internal
WITH_PMIX=internal

# Site-specific optional integrations. Leave empty for a portable build; set to
# a prefix path such as /usr or /opt/ucx when the matching development headers
# are available on the target platform. Set ENABLE_OSHMEM=yes only when UCX is
# available; otherwise OpenSHMEM configure will abort.
WITH_UCX=
WITH_SLURM=

# -----------------------------
# Project paths
# -----------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ZIP_FILE="${SCRIPT_DIR}/openmpi.zip"
OPT_DIR="${SCRIPT_DIR}/opt"
INSTALL_PREFIX="${OPT_DIR}/openmpi"

BUILD_ROOT="${SCRIPT_DIR}/.build_openmpi"

echo "==> Building OpenMPI"
echo "    CC=${CC}"
echo "    CXX=${CXX}"
echo "    FC=${FC}"
echo "    CFLAGS=${CFLAGS}"
echo "    CXXFLAGS=${CXXFLAGS}"
echo "    FCFLAGS=${FCFLAGS}"
echo "    LDFLAGS=${LDFLAGS}"
echo "    ENABLE_MPI_FORTRAN=${ENABLE_MPI_FORTRAN}"
echo "    ENABLE_OSHMEM=${ENABLE_OSHMEM}"
echo "    ENABLE_SHARED=${ENABLE_SHARED}"
echo "    ENABLE_STATIC=${ENABLE_STATIC}"
echo "    ENABLE_MPI_JAVA=${ENABLE_MPI_JAVA}"
echo "    ENABLE_IPV6=${ENABLE_IPV6}"
echo "    WITH_HWLOC=${WITH_HWLOC}"
echo "    WITH_LIBEVENT=${WITH_LIBEVENT}"
echo "    WITH_PMIX=${WITH_PMIX}"
echo "    WITH_UCX=${WITH_UCX:-none}"
echo "    WITH_SLURM=${WITH_SLURM:-none}"
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
  find "${BUILD_ROOT}" -mindepth 1 -maxdepth 4 -type f -path '*/ompi/include/mpi.h.in' -print -quit |
  sed 's#/ompi/include/mpi.h.in$##'
)"

if [[ -z "${SRC_DIR}" || ! -x "${SRC_DIR}/configure" || ! -d "${SRC_DIR}/ompi" ]]; then
  echo "Error: could not find OpenMPI top-level source directory after unzipping ${ZIP_FILE}." >&2
  exit 1
fi

echo "==> Source directory: ${SRC_DIR}"
cd "${SRC_DIR}"

# Open MPI 5.0.10 forces recursive inlining that GCC 16 rejects.
# Apply the upstream fix after each fresh extraction, before configuration.
if grep -qx 'major=5' VERSION && grep -qx 'minor=0' VERSION &&
   grep -qx 'release=10' VERSION; then
  echo "==> Applying OpenMPI 5.0.10 GCC 16 inline compatibility fix"
  patch -p1 < "${SCRIPT_DIR}/patches/openmpi-5.0.10-gcc16-inline.patch"
fi

CONFIGURE_ARGS=(
  "--prefix=${INSTALL_PREFIX}"
  "CC=${CC}"
  "CXX=${CXX}"
  "FC=${FC}"
  "CFLAGS=${CFLAGS}"
  "CXXFLAGS=${CXXFLAGS}"
  "FCFLAGS=${FCFLAGS}"
  "LDFLAGS=${LDFLAGS}"
  "--enable-mpi-fortran=${ENABLE_MPI_FORTRAN}"
  "--enable-oshmem=${ENABLE_OSHMEM}"
  "--enable-shared=${ENABLE_SHARED}"
  "--enable-static=${ENABLE_STATIC}"
  "--enable-mpi-java=${ENABLE_MPI_JAVA}"
  "--enable-ipv6=${ENABLE_IPV6}"
  "--enable-wrapper-rpath=${ENABLE_WRAPPER_RPATH}"
  "--enable-wrapper-runpath=${ENABLE_WRAPPER_RUNPATH}"
  "--enable-mpirun-prefix-by-default=${ENABLE_MPIRUN_PREFIX_BY_DEFAULT}"
  "--with-hwloc=${WITH_HWLOC}"
  "--with-libevent=${WITH_LIBEVENT}"
  "--with-pmix=${WITH_PMIX}"
)

if [[ -n "${WITH_UCX}" ]]; then
  CONFIGURE_ARGS+=("--with-ucx=${WITH_UCX}")
fi

if [[ -n "${WITH_SLURM}" ]]; then
  CONFIGURE_ARGS+=("--with-slurm=${WITH_SLURM}")
fi

echo "==> Configuring"
./configure "${CONFIGURE_ARGS[@]}"

echo "==> Compiling with ${JOBS} jobs"
make -j"${JOBS}"

echo "==> Installing"
make install

echo "==> Verifying installation"
"${INSTALL_PREFIX}/bin/mpirun" --version
"${INSTALL_PREFIX}/bin/mpif90" --showme:command
"${INSTALL_PREFIX}/bin/mpif90" --showme:compile
"${INSTALL_PREFIX}/bin/mpif90" --showme:link

echo "==> Cleaning extracted source"
cd "${SCRIPT_DIR}"
rm -rf "${BUILD_ROOT}"

echo "==> Done. OpenMPI installed at ${INSTALL_PREFIX}"
