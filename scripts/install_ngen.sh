#!/usr/bin/env bash
# =============================================================================
# install_ngen.sh — NGEN source build following the SYMFLUENCE install pattern
#
# Designed to be run INSIDE the running container by the jovyan user.
# All build dependencies (gcc, cmake, netcdf-devel, etc.) are pre-installed
# in the image; this script only performs the clone, configure, and compile.
#
# ENVIRONMENT VARIABLES (all optional — defaults shown):
#
#   INSTALL_DIR    — where to clone and build ngen
#                    default: /opt/ngen
#   NGEN_REPO      — GitHub slug for the ngen repository
#                    default: CIROH-UA/ngen
#   NGEN_BRANCH    — branch to clone
#                    default: ngiab
#   BOOST_VERSION  — Boost version to download locally (SYMFLUENCE pins 1.79.0)
#                    default: 1.79.0
#   NCORES         — parallel build jobs
#                    default: 4
#   WITH_FORTRAN   — 1 to enable Fortran BMI modules (Noah-OWP, SAC-SMA, Snow-17)
#                    default: 1
#   WITH_PYTHON    — 1 to enable Python bindings + t-route routing
#                    default: 1  (auto-disabled if NumPy >= 2 is detected)
#   PYTHON_EXE     — Python executable to pass to CMake
#                    default: python3
#
# USAGE:
#   install_ngen.sh
#   INSTALL_DIR=/home/jovyan/ngen NCORES=8 install_ngen.sh
#   WITH_PYTHON=0 install_ngen.sh
# =============================================================================

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
INSTALL_DIR="${INSTALL_DIR:-/opt/ngen}"
NGEN_REPO="${NGEN_REPO:-CIROH-UA/ngen}"
NGEN_BRANCH="${NGEN_BRANCH:-ngiab}"
BOOST_VERSION="${BOOST_VERSION:-1.79.0}"
NCORES="${NCORES:-4}"
WITH_FORTRAN="${WITH_FORTRAN:-1}"
WITH_PYTHON="${WITH_PYTHON:-1}"
PYTHON_EXE="${PYTHON_EXE:-python3}"

# Derived
BOOST_UNDERSCORE="${BOOST_VERSION//./_}"   # e.g. 1_79_0
BOOST_DIR="boost_${BOOST_UNDERSCORE}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
info()  { echo "[NGEN] $*"; }
warn()  { echo "[NGEN WARN] $*" >&2; }
die()   { echo "[NGEN ERROR] $*" >&2; exit 1; }

# ---------------------------------------------------------------------------
# Step 0 — Pre-flight dependency checks
# ---------------------------------------------------------------------------
info "=== Step 0: Checking required tools ==="

check_cmd() {
    command -v "$1" &>/dev/null || die "Required command not found: $1 — ensure build dependencies are installed in the image."
}

check_cmd cmake
check_cmd gcc
check_cmd g++
check_cmd git
check_cmd make
check_cmd wget

# Verify NetCDF (nc-config must be on PATH)
if ! command -v nc-config &>/dev/null; then
    die "nc-config not found. Ensure netcdf-devel is installed. Cannot build with NETCDF support."
fi

# Verify Fortran compiler if enabled
if [[ "$WITH_FORTRAN" == "1" ]]; then
    if ! command -v gfortran &>/dev/null; then
        warn "gfortran not found — disabling Fortran BMI modules (Noah-OWP, SAC-SMA, Snow-17)."
        WITH_FORTRAN=0
    else
        FC=$(command -v gfortran)
        info "Fortran compiler: $FC"
    fi
fi

# Verify Python if enabled, and guard against NumPy >= 2
if [[ "$WITH_PYTHON" == "1" ]]; then
    if ! command -v "$PYTHON_EXE" &>/dev/null; then
        warn "$PYTHON_EXE not found — disabling Python bindings and t-route routing."
        WITH_PYTHON=0
    else
        NUMPY_MAJOR=$("$PYTHON_EXE" -c "import numpy; print(numpy.__version__.split('.')[0])" 2>/dev/null || echo "unknown")
        if [[ "$NUMPY_MAJOR" == "2" ]]; then
            warn "NumPy 2.x detected — NGEN does not yet support NumPy 2. Disabling -DNGEN_WITH_PYTHON and -DNGEN_WITH_ROUTING."
            WITH_PYTHON=0
        elif [[ "$NUMPY_MAJOR" == "unknown" ]]; then
            warn "NumPy not importable via $PYTHON_EXE — disabling Python/routing flags."
            WITH_PYTHON=0
        else
            info "NumPy version: $("$PYTHON_EXE" -c 'import numpy; print(numpy.__version__)')"
        fi
    fi
fi

info "Build configuration:"
info "  INSTALL_DIR  : $INSTALL_DIR"
info "  NGEN_REPO    : $NGEN_REPO (branch: $NGEN_BRANCH)"
info "  BOOST_VERSION: $BOOST_VERSION"
info "  NCORES       : $NCORES"
info "  WITH_FORTRAN : $WITH_FORTRAN"
info "  WITH_PYTHON  : $WITH_PYTHON"
info ""

# ---------------------------------------------------------------------------
# Step 1 — Clone NGEN
# ---------------------------------------------------------------------------
info "=== Step 1: Cloning NGEN ==="
mkdir -p "$INSTALL_DIR"

if [[ -d "$INSTALL_DIR/.git" ]]; then
    warn "NGEN repo already cloned at $INSTALL_DIR — skipping clone."
else
    git clone --depth 1 -b "$NGEN_BRANCH" "https://github.com/${NGEN_REPO}.git" "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"

# ---------------------------------------------------------------------------
# Step 2 — Initialize submodules
# ---------------------------------------------------------------------------
info "=== Step 2: Initializing submodules ==="

# Required build/test submodules
git submodule update --init --recursive -- test/googletest extern/pybind11 || true

# BMI modules
git submodule update --init --recursive -- \
    extern/cfe \
    extern/evapotranspiration \
    extern/sloth \
    extern/noah-owp-modular || true

# t-route (non-recursive; avoids spurious make calls on some systems)
git submodule update --init -- extern/t-route || warn "t-route submodule init failed — routing Python packages will be skipped."

# Fortran BMI wrapper
if [[ "$WITH_FORTRAN" == "1" ]]; then
    git submodule update --init --recursive -- extern/iso_c_fortran_bmi || true
fi

# Optional extra models
git submodule update --init --recursive -- extern/topmodel || true
git submodule update --init --recursive -- extern/sac-sma  || true
git submodule update --init --recursive -- extern/snow17   || true

# ---------------------------------------------------------------------------
# Step 3 — Fallback-clone any missing BMI modules
# ---------------------------------------------------------------------------
info "=== Step 3: Fallback-cloning any missing BMI modules ==="

clone_if_missing() {
    local check_file="$1"
    local target_dir="$2"
    local repo_url="$3"
    if [[ ! -f "$check_file" ]]; then
        warn "Submodule $target_dir missing — cloning directly from $repo_url"
        git clone --depth 1 "$repo_url" "$target_dir"
    fi
}

clone_if_missing extern/cfe/CMakeLists.txt \
    extern/cfe \
    https://github.com/NOAA-OWP/cfe.git

clone_if_missing extern/sloth/CMakeLists.txt \
    extern/sloth \
    https://github.com/NOAA-OWP/SLoTH.git

# PET lives one directory deeper than standard
if [[ ! -d extern/evapotranspiration/evapotranspiration ]]; then
    warn "PET submodule missing — cloning directly."
    git clone --depth 1 https://github.com/NOAA-OWP/evapotranspiration.git \
        extern/evapotranspiration/evapotranspiration
fi

clone_if_missing extern/noah-owp-modular/CMakeLists.txt \
    extern/noah-owp-modular \
    https://github.com/NOAA-OWP/noah-owp-modular.git

if [[ "$WITH_FORTRAN" == "1" ]]; then
    clone_if_missing extern/iso_c_fortran_bmi/CMakeLists.txt \
        extern/iso_c_fortran_bmi \
        https://github.com/NOAA-OWP/iso_c_fortran_bmi.git
fi

clone_if_missing extern/topmodel/CMakeLists.txt \
    extern/topmodel \
    https://github.com/NOAA-OWP/topmodel.git

clone_if_missing extern/sac-sma/CMakeLists.txt \
    extern/sac-sma \
    https://github.com/NOAA-OWP/sac-sma.git

clone_if_missing extern/snow17/CMakeLists.txt \
    extern/snow17 \
    https://github.com/NOAA-OWP/snow17.git

# ---------------------------------------------------------------------------
# Step 4 — Fetch Boost 1.79.0 (SYMFLUENCE pinned version)
# ---------------------------------------------------------------------------
info "=== Step 4: Fetching Boost ${BOOST_VERSION} ==="

if [[ -d "${BOOST_DIR}" ]]; then
    info "Boost directory already present — skipping download."
else
    wget -q "https://downloads.sourceforge.net/project/boost/boost/${BOOST_VERSION}/${BOOST_DIR}.tar.bz2"
    tar -xjf "${BOOST_DIR}.tar.bz2"
    rm -f "${BOOST_DIR}.tar.bz2"
fi

export BOOST_ROOT="${INSTALL_DIR}/${BOOST_DIR}"
info "BOOST_ROOT=$BOOST_ROOT"

# ---------------------------------------------------------------------------
# Step 5 — CMake configure and build NGEN
# ---------------------------------------------------------------------------
info "=== Step 5: Configuring and building NGEN ==="

# Unset MAKEFLAGS/MAKELEVEL to prevent spurious recursive make calls
unset MAKEFLAGS MAKELEVEL 2>/dev/null || true

# Build the CMake argument list
CMAKE_ARGS=(
    -DCMAKE_BUILD_TYPE=Release
    -DBOOST_ROOT="$BOOST_ROOT"
    -DNGEN_WITH_SQLITE3=ON
    -DNGEN_WITH_BMI_C=ON
    -DNGEN_WITH_BMI_CPP=ON
    -DNGEN_WITH_NETCDF=ON
    -DCMAKE_POLICY_VERSION_MINIMUM=3.5
)

if [[ "$WITH_FORTRAN" == "1" ]]; then
    ISO_C_BMI_DIR="${INSTALL_DIR}/extern/iso_c_fortran_bmi"
    CMAKE_ARGS+=(
        -DNGEN_WITH_BMI_FORTRAN=ON
        -DCMAKE_Fortran_COMPILER="$FC"
        -DBMI_FORTRAN_ISO_C_LIB_DIR="${ISO_C_BMI_DIR}/cmake_build"
        -DBMI_FORTRAN_ISO_C_LIB_NAME=iso_c_bmi
    )
fi

if [[ "$WITH_PYTHON" == "1" ]]; then
    CMAKE_ARGS+=(
        -DNGEN_WITH_PYTHON=ON
        -DPython3_EXECUTABLE="$PYTHON_EXE"
        -DNGEN_WITH_ROUTING=ON
    )
fi

cmake "${CMAKE_ARGS[@]}" -S . -B cmake_build
cmake --build cmake_build --target ngen -j "$NCORES"

# If the Python-enabled build fails, retry without Python/routing
if [[ $? -ne 0 && "$WITH_PYTHON" == "1" ]]; then
    warn "CMake build failed with Python enabled — retrying without Python/routing flags."
    CMAKE_ARGS_NOPY=()
    for arg in "${CMAKE_ARGS[@]}"; do
        case "$arg" in
            -DNGEN_WITH_PYTHON*|-DPython3_EXECUTABLE*|-DNGEN_WITH_ROUTING*) ;;
            *) CMAKE_ARGS_NOPY+=("$arg") ;;
        esac
    done
    CMAKE_ARGS_NOPY+=(-DNGEN_WITH_PYTHON=OFF -DNGEN_WITH_ROUTING=OFF)
    cmake "${CMAKE_ARGS_NOPY[@]}" -S . -B cmake_build
    cmake --build cmake_build --target ngen -j "$NCORES"
fi

# ---------------------------------------------------------------------------
# Step 6 — Build BMI shared libraries (each non-fatal)
# ---------------------------------------------------------------------------
info "=== Step 6: Building BMI shared libraries ==="

build_bmi() {
    local name="$1"
    local dir="$2"
    shift 2
    local extra_cmake_args=("$@")
    info "  Building $name..."
    (
        cd "$dir"
        rm -rf cmake_build && mkdir cmake_build
        cmake -DCMAKE_BUILD_TYPE=Release "${extra_cmake_args[@]}" -S . -B cmake_build \
            && cmake --build cmake_build -j "$NCORES"
    ) || warn "  $name build failed (non-fatal — continuing)."
}

# iso_c_fortran_bmi FIRST — required by all Fortran modules
if [[ "$WITH_FORTRAN" == "1" ]]; then
    build_bmi "iso_c_fortran_bmi" extern/iso_c_fortran_bmi \
        -DCMAKE_Fortran_COMPILER="$FC"
fi

# C modules
build_bmi "CFE"      extern/cfe
build_bmi "SLOTH"    extern/sloth
build_bmi "PET"      extern/evapotranspiration/evapotranspiration
build_bmi "TOPMODEL" extern/topmodel

# Fortran modules (depend on iso_c_fortran_bmi)
if [[ "$WITH_FORTRAN" == "1" ]]; then
    build_bmi "Noah-OWP-Modular" extern/noah-owp-modular \
        -DCMAKE_Fortran_COMPILER="$FC" \
        -DNGEN_IS_MAIN_PROJECT=ON

    build_bmi "SAC-SMA" extern/sac-sma \
        -DCMAKE_Fortran_COMPILER="$FC" \
        -DNGEN_IS_MAIN_PROJECT=ON

    ISO_C_FULL="${INSTALL_DIR}/extern/iso_c_fortran_bmi"
    build_bmi "Snow-17" extern/snow17 \
        -DCMAKE_Fortran_COMPILER="$FC" \
        -DNGEN_IS_MAIN_PROJECT=ON \
        -DISO_C_FORTRAN_BMI_PATH:PATH="$ISO_C_FULL"
fi

# ---------------------------------------------------------------------------
# Step 7 — Install t-route Python routing packages (optional)
# ---------------------------------------------------------------------------
info "=== Step 7: Installing t-route Python routing packages ==="

if [[ "$WITH_PYTHON" == "1" && -d extern/t-route/src ]]; then
    "$PYTHON_EXE" -m pip install -e extern/t-route/src/python_routing_v02  || warn "t-route python_routing_v02 install failed."
    "$PYTHON_EXE" -m pip install -e extern/t-route/src/python_framework_v02 || warn "t-route python_framework_v02 install failed."
    "$PYTHON_EXE" -m pip install -e extern/t-route/src/nwm_routing          || warn "t-route nwm_routing install failed."
    "$PYTHON_EXE" -m pip install -e extern/t-route/src/ngen_routing --no-deps || warn "t-route ngen_routing install failed."
else
    info "  Skipping t-route (Python disabled or extern/t-route/src not present)."
fi

# ---------------------------------------------------------------------------
# Step 8 — Verification
# ---------------------------------------------------------------------------
info ""
info "=== Step 8: Verification ==="

echo ""
echo "-------------------------------------------------------------------"
echo " NGEN build complete — verification"
echo "-------------------------------------------------------------------"
echo ""

# ngen binary
if [[ -f cmake_build/ngen ]]; then
    echo "[OK]  ngen binary:    $INSTALL_DIR/cmake_build/ngen"
    echo "      Help output:"
    cmake_build/ngen --help 2>&1 | head -5 || true
else
    echo "[FAIL] ngen binary not found at cmake_build/ngen"
fi

echo ""

# Key BMI shared libraries
for lib_glob in \
    "extern/cfe/cmake_build/libcfebmi.*" \
    "extern/sloth/cmake_build/libslothmodel.*" \
    "extern/evapotranspiration/evapotranspiration/cmake_build/libpetbmi.*" \
    "extern/topmodel/cmake_build/libtopmodelbmi.*" \
    "extern/iso_c_fortran_bmi/cmake_build/libiso_c_bmi.*" \
    "extern/noah-owp-modular/cmake_build/libsurfacebmi.*" \
    "extern/sac-sma/cmake_build/libsacbmi.*" \
    "extern/snow17/cmake_build/libsnow17_bmi.*"
do
    found=$(ls ${lib_glob} 2>/dev/null | head -1 || true)
    if [[ -n "$found" ]]; then
        echo "[OK]  $found"
    else
        echo "[--]  $lib_glob  (not built or skipped)"
    fi
done

echo ""

# t-route Python import check
if [[ "$WITH_PYTHON" == "1" ]]; then
    "$PYTHON_EXE" -c "import ngen_routing; print('[OK]  t-route / ngen_routing importable')" 2>/dev/null \
        || echo "[--]  ngen_routing not importable (t-route may have been skipped)"
fi

echo ""
echo "-------------------------------------------------------------------"
echo " ngen executable : $INSTALL_DIR/cmake_build/ngen"
echo " BMI libraries   : $INSTALL_DIR/extern/*/cmake_build/*.so"
echo ""
echo " To run ngen:"
echo "   $INSTALL_DIR/cmake_build/ngen <catchments.geojson> <nexus.geojson> <realization.json>"
echo ""
echo " NGEN install path for SYMFLUENCE config:"
echo "   install_path: \"$INSTALL_DIR\""
echo "-------------------------------------------------------------------"
