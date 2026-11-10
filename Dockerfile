#
# HEFS-FEWS-Hub Container Image Description
#
# This container image is designed to support the exploration of HEFS ensembles using FEWS within a JupyterHub environment, as part of the CIROH-supported project.
#
# **Operating System:**
#   - Based on AlmaLinux 8.10, chosen because FEWS officially supports Red Hat-based distributions, ensuring compatibility and stability for FEWS binaries.
#
# **JupyterLab Setup:**
#   - Installs Miniconda and creates a dedicated Python environment for running JupyterLab and related Python tools.
#   - JupyterLab is configured to run as the main user interface, providing access to notebooks and Python scripts for data analysis and dashboarding.
#
# **XFCE and VNC Desktop Environment:**
#   - Installs a minimal XFCE desktop environment, providing a lightweight and user-friendly graphical interface.
#   - TurboVNC is used to enable remote desktop access, allowing users to interact with the desktop environment through their browser or a VNC client.
#   - This setup allows users to launch and interact with the FEWS standalone application in a familiar desktop environment, directly from the cloud.
#
# **Additional Features:**
#   - Includes AWS CLI for data access, Node.js for JupyterLab extensions, and other utilities (e.g., nano, Thunar file manager).
#   - FEWS binaries and panel application tools are pre-installed, with desktop shortcuts for easy access.
#
# This image is intended for use on TEEHRHub or similar JupyterHub deployments, providing a seamless environment for hydrologic model execution and analysis.

FROM almalinux:8.10 AS base
# FROM 935462133478.dkr.ecr.us-east-2.amazonaws.com/teehr:v0.4-beta

USER root
# Install EPEL repository for additional packages
RUN --mount=type=cache,target=/var/cache/dnf \
    dnf install -y epel-release dnf-plugins-core && \
    dnf config-manager --set-enabled powertools

# Install XFCE components individually to save space
RUN --mount=type=cache,target=/var/cache/dnf \
    dnf install -y --enablerepo=epel \
    dpkg \
    dbus-x11 \
    xfce4-session \
    xfce4-panel \
    xfce4-settings \
    xfdesktop \
    xfwm4 \
    xfce4-terminal \
    featherpad \
    nano \
    Thunar \
    xorg-x11-server-Xorg \
    xorg-x11-xinit \
    xorg-x11-xauth \
    xorg-x11-fonts-* \
    xorg-x11-utils \
    curl \
    wget \
    git-lfs \
    perl \
    unzip \
    vim \
    libgfortran \
    sqlite \
    bzip2 \
    expat \
    udunits2 \
    zlib \
    libaec \
    mpich \
    hdf5 \
    netcdf \
    netcdf-fortran \
    netcdf-cxx \
    netcdf-cxx4-mpich \
    openblas \
    python3.11 \
    python3.11-devel \
    python3.11-pip \
    which \
    gdb \
    lldb && \
    # Keep the installed x86_64 and requested i686 libstdc++ at the same RPM version.
    dnf upgrade -y libstdc++ && \
    wget https://repo.almalinux.org/almalinux/8/AppStream/x86_64/os/Packages/compat-libgfortran-48-4.8.5-36.1.el8.i686.rpm && \
    dpkg --add-architecture i386 && \
    dnf -y install compat-libgfortran-48-4.8.5-36.1.el8.i686.rpm \
    libstdc++.i686 \
    glibc.i686 && \
    rm compat-libgfortran-48-4.8.5-36.1.el8.i686.rpm && \
    dnf clean all

RUN python3.11 -m pip install "numpy<2.0"

ENV PATH="/root/.cargo/bin:${PATH}"
ENV UV_INSTALL_DIR=/root/.cargo/bin
ENV UV_COMPILE_BYTECODE=1
RUN curl -LsSf https://astral.sh/uv/install.sh | sh
RUN uv self update

# ===========================================================
# STAGE 2: NGEN Compilation Base (Development Headers)
# ===========================================================
FROM base AS build_base
RUN --mount=type=cache,target=/var/cache/dnf \
    dnf install -y \
    sudo \
    gcc \
    gcc-c++ \
    make \
    cmake \
    tar \
    git \
    gcc-gfortran \
    sqlite-devel \
    expat-devel \
    flex \
    bison \
    udunits2-devel \
    zlib-devel \
    wget \
    mpich-devel \
    hdf5-devel \
    netcdf-devel \
    netcdf-fortran-devel \
    netcdf-cxx-devel \
    lld \
    clang \
    openblas-devel \
    unzip \
    gcc-toolset-13-gcc-gfortran \
    gdb && \
    dnf clean all
# AlmaLinux 8 ships ninja 1.8.2; Fortran support requires 1.10+
RUN wget -q https://github.com/ninja-build/ninja/releases/download/v1.11.1/ninja-linux.zip && \
    unzip ninja-linux.zip -d /usr/local/bin && \
    rm ninja-linux.zip
# Use GCC 13 gfortran to fix preprocessor apostrophe-in-comment bug in gfortran 8.x #???
ENV PATH="/opt/rh/gcc-toolset-13/root/usr/bin:${PATH}" 

# ===========================================================
# STAGE 3: NGEN Dependency Compilations (Boost, T-Route, NGEN)
# ===========================================================
FROM build_base AS boost_build
RUN wget https://archives.boost.io/release/1.86.0/source/boost_1_86_0.tar.gz && \
    tar -xzf boost_1_86_0.tar.gz && \
    cd boost_1_86_0 && ./bootstrap.sh && ./b2 -j"$(nproc)" install
    # cd boost_1_86_0 && ./bootstrap.sh && ./b2 headers
ENV BOOST_ROOT=/boost_1_86_0

FROM boost_build AS troute_prebuild
WORKDIR /ngen
ENV FC=gfortran NETCDF=/usr/lib64/gfortran/modules/
RUN ln -s /usr/bin/python3.11 /usr/bin/python || true
RUN uv venv -p 3.11
ENV PATH="/ngen/.venv/bin:$PATH"
ADD https://api.github.com/repos/${TROUTE_REPO}/git/refs/heads/${TROUTE_BRANCH} /tmp/version.json 
#curl https://api.github.com/repos/${TROUTE_REPO}/git/refs/heads/${TROUTE_BRANCH} > /tmp/version.json
RUN uv pip install -r https://raw.githubusercontent.com/$TROUTE_REPO/refs/heads/$TROUTE_BRANCH/requirements.txt



FROM troute_prebuild AS troute_build
WORKDIR /ngen/t-route
ENV CFLAGS="-g -O0" CXXFLAGS="-g -O0" FFLAGS="-g -O0"
RUN git clone --depth 1 --single-branch --branch $TROUTE_BRANCH https://github.com/$TROUTE_REPO.git . && \
    git submodule update --init --depth 1 && \
    uv pip install build wheel && \
    sed -i 's/build_[a-z]*=/#&/' compiler.sh && \
    ./compiler.sh no-e && \
    uv pip install --config-setting='--build-option=--use-cython' src/troute-network/ && \
    cd src/troute-network && uv build --wheel --config-setting='--build-option=--use-cython' && cd /ngen/t-route && \
    uv pip install --no-build-isolation --config-setting='--build-option=--use-cython' src/troute-routing/ && \
    cd src/troute-routing && uv build --wheel --no-build-isolation --config-setting='--build-option=--use-cython' && cd /ngen/t-route && \
    cd src/troute-config && uv build --wheel --no-build-isolation && cd /ngen/t-route && \
    cd src/troute-nwm && uv build --wheel --no-build-isolation && cd /ngen/t-route && \
    mkdir -p /wheels && find /ngen/t-route/src/troute-*/dist -name "*.whl" -exec cp {} /wheels/ \;

# FROM boost_build AS ngen_clone
# NGIAB docker does it from troute_prebuild, not boost_build. Wondering if this will solve some env issues?
FROM troute_prebuild AS ngen_clone
WORKDIR /ngen
ADD https://api.github.com/repos/${NGEN_REPO}/git/refs/heads/${NGEN_BRANCH} /tmp/version.json
#curl https://api.github.com/repos/${NGEN_REPO}/git/refs/heads/${NGEN_BRANCH} > /tmp/version.json
RUN git clone --single-branch --branch $NGEN_BRANCH https://github.com/$NGEN_REPO.git && \
    cd ngen && \
    git submodule update --init --recursive --depth 1

FROM ngen_clone AS ngen_build
ENV PATH=${PATH}:/usr/lib64/mpich/bin
ENV CXXFLAGS="-fuse-ld=lld -g -O0" CFLAGS="-g -O0" FFLAGS="-g -O0"
WORKDIR /ngen/ngen
ARG COMMON_BUILD_ARGS="-DNGEN_WITH_EXTERN_ALL=ON -DNGEN_WITH_NETCDF:BOOL=ON -DNGEN_WITH_BMI_C:BOOL=ON -DNGEN_WITH_BMI_FORTRAN:BOOL=ON -DNGEN_WITH_PYTHON:BOOL=ON -DNGEN_WITH_ROUTING:BOOL=ON -DNGEN_WITH_SQLITE:BOOL=ON -DNGEN_WITH_UDUNITS:BOOL=ON -DUDUNITS_QUIET:BOOL=ON -DNGEN_WITH_TESTS:BOOL=OFF -DCMAKE_BUILD_TYPE=Debug -DCMAKE_INSTALL_PREFIX=. -DPython_EXECUTABLE=/usr/bin/python3.11"
RUN cmake -G Ninja -B cmake_build_serial -S . ${COMMON_BUILD_ARGS} -DNGEN_WITH_MPI:BOOL=OFF && \
    cmake --build cmake_build_serial --target all -- -j $(nproc)

ARG MPI_BUILD_ARGS="-DNGEN_WITH_MPI:BOOL=ON -DNetCDF_ROOT=/usr/lib64/mpich -DCMAKE_PREFIX_PATH=/usr/lib64/mpich -DCMAKE_LIBRARY_PATH=/usr/lib64/mpich/lib"
RUN dnf install -y netcdf-cxx4-mpich-devel
RUN cmake -G Ninja -B cmake_build_parallel -S . ${COMMON_BUILD_ARGS} ${MPI_BUILD_ARGS} \
    -DNetCDF_CXX_INCLUDE_DIR=/usr/include/mpich-$(arch) \
    -DNetCDF_INCLUDE_DIR=/usr/include/mpich-$(arch) && \
    cmake --build cmake_build_parallel --target all -- -j $(nproc)

FROM ngen_clone AS build_sundials
WORKDIR /sundials
ENV SUNDIALS_VERSION=7.5.0
RUN wget https://github.com/LLNL/sundials/releases/download/v${SUNDIALS_VERSION}/sundials-${SUNDIALS_VERSION}.tar.gz && \
    tar -xzf sundials-${SUNDIALS_VERSION}.tar.gz && \
    cmake -G Ninja -B build_sundials sundials-${SUNDIALS_VERSION} -DEXAMPLES_ENABLE_C=OFF -DEXAMPLES_ENABLE_F2003=OFF -DBUILD_FORTRAN_MODULE_INTERFACE=ON -DCMAKE_Fortran_COMPILER=gfortran -DCMAKE_BUILD_TYPE=Debug -DCMAKE_INSTALL_PREFIX=/sundials/install && \
    cmake --build build_sundials --target all -- -j $(nproc) && \
    cmake --build build_sundials --target install

FROM build_sundials AS build_summa
WORKDIR /ngen/ngen/extern/summa
RUN cmake -G Ninja -B build_summa -DUSE_NEXTGEN=ON -DUSE_SUNDIALS=ON -DSPECIFY_LAPACK_LINKS=OFF -DCMAKE_BUILD_TYPE=Debug -DNetCDF_F90_INCLUDE_DIR=/usr/lib64/gfortran/modules/ -DOpenBLAS_INCLUDE_DIR=/usr/include/openblas -DSUNDIALS_DIR=/sundials/build_sundials/ -DCMAKE_Fortran_COMPILER=gfortran -DCMAKE_Fortran_FLAGS="-g -O0" && \
    cmake --build build_summa --target all -- -j $(nproc)

FROM ngen_clone AS build_sacsma
WORKDIR /ngen/ngen/extern/sac-sma
RUN cmake -B cmake_build -DISO_C_FORTRAN_BMI_PATH=/ngen/ngen/extern/iso_c_fortran_bmi -S . && \
    cmake --build cmake_build -j $(nproc)

FROM ngen_clone AS build_snow17
WORKDIR /ngen/ngen/extern/snow17
RUN cmake -B cmake_build -DISO_C_FORTRAN_BMI_PATH=/ngen/ngen/extern/iso_c_fortran_bmi -S . && \
    cmake --build cmake_build -j $(nproc)

# ===========================================================
# STAGE 4: Aggregate NGEN Artifacts
# ===========================================================
FROM ngen_build AS restructure_files
RUN mkdir -p /dmod/datasets /dmod/datasets/static /dmod/shared_libs /dmod/bin /dmod/utils/ && \
    shopt -s globstar && \
    cp -a ./extern/**/cmake_build/*.so* /dmod/shared_libs/. || true && \
    cp -a ./extern/noah-owp-modular/**/*.TBL /dmod/datasets/static && \
    cp -a ./extern/lgar-c/LGAR-C/data/vG_default_params.dat /dmod/datasets/static && \
    cp -a ./cmake_build_parallel/ngen /dmod/bin/ngen-parallel || true && \
    cp -a ./cmake_build_serial/ngen /dmod/bin/ngen-serial || true && \
    cp -a ./cmake_build_parallel/partitionGenerator /dmod/bin/partitionGenerator || true && \
    cp -ar ./utilities/* /dmod/utils/ && \
    cd /dmod/bin && (stat ngen-parallel && ln -s ngen-parallel ngen) || (stat ngen-serial && ln -s ngen-serial ngen)

COPY --from=build_summa /ngen/ngen/extern/summa/build_summa/*.so /dmod/shared_libs/
COPY --from=build_sacsma /ngen/ngen/extern/sac-sma/cmake_build/*.so /dmod/shared_libs/
COPY --from=build_snow17 /ngen/ngen/extern/snow17/cmake_build/*.so /dmod/shared_libs/

# ===========================================================
# STAGE 5: Final Target (Unchanged HEFS-FEWS-Hub + NGEN Copies)
# ===========================================================
FROM build_base AS final
ARG pinned_python_packages="netCDF4==1.6.3 pydantic<2 pandas<3"
USER root

# RUN --mount=type=cache,target=/var/cache/dnf \
#     dnf install -y hdf5-devel netcdf-devel netcdf-fortran-devel netcdf-cxx-devel netcdf-cxx4-mpich-devel

# RUN python3.11 -m pip install mpi4py

# RUN HDF5_DIR=/usr NETCDF4_DIR=/usr/lib64/mpich MPICC=mpicc CC=mpicc USE_NCCONFIG=1 \
#     python3.11 -m pip install --no-cache-dir \
#     -r https://raw.githubusercontent.com/$TROUTE_REPO/refs/heads/$TROUTE_BRANCH/requirements.txt

# RUN python3.11 -m pip install "numpy<2.0"
ENV CONDA_ENV=notebook \
    NB_USER=jovyan \
    NB_UID=1000 \
    NB_GID=100 \
    CONDA_DIR=/opt/conda \
    SHELL=/bin/bash \
    # Add TZ configuration - https://github.com/PrefectHQ/prefect/issues/3061
    TZ=UTC

# Run conda activate each time a bash shell starts, so users don't have to manually type conda activate
# Note this is only read by shell, but not by the jupyter notebook - that relies
# on us starting the correct `python` process, which we do by adding the notebook conda environment's
# bin to PATH earlier ($NB_PYTHON_PREFIX/bin)
RUN echo ". ${CONDA_DIR}/etc/profile.d/conda.sh ; conda activate ${CONDA_ENV}" > /etc/profile.d/init_conda.sh
    
# Create jovyan user
RUN groupadd -g ${NB_GID} ${NB_USER} || true \
    && useradd -m -s /bin/bash -u ${NB_UID} -g ${NB_GID} ${NB_USER} \
    && mkdir -p /home/${NB_USER}

# ===========================================================
# Setup Python Environment
# ===========================================================

ENV PATH=${CONDA_DIR}/bin:${PATH}
RUN chown -R ${NB_USER}:${NB_GID} /opt/
# Install latest mambaforge in ${CONDA_DIR}
RUN echo "Installing Miniforge..." \
    && URL="https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-$(uname -m).sh" \
    && wget --quiet ${URL} -O installer.sh \
    && /bin/bash installer.sh -u -b -p ${CONDA_DIR} \
    && rm installer.sh \
    # && mamba install conda-lock -y \
    && ${CONDA_DIR}/bin/mamba clean -afy \
    # After installing the packages, we cleanup some unnecessary files
    # to try reduce image size - see https://jcristharif.com/conda-docker-tips.html
    # Although we explicitly do *not* delete .pyc files, as that seems to slow down startup
    # quite a bit unfortunately - see https://github.com/2i2c-org/infrastructure/issues/2047
    && find ${CONDA_DIR} -follow -type f -name '*.a' -delete


# Install Miniconda (for mamba/conda)
# RUN --mount=type=cache,target=/root/.conda/pkgs \
#     wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh \
#     && bash /tmp/miniconda.sh -b -p ${CONDA_DIR} \
#     && rm /tmp/miniconda.sh \
#     && conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main \
#     && conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r

# Create environment and install packages
RUN --mount=type=cache,target=/opt/conda/pkgs \
    ${CONDA_DIR}/bin/mamba create -n ${CONDA_ENV} -y python=3.12 \
    gcc_linux-64 \
    gxx_linux-64 \
    libstdcxx-ng \
    libgcc-ng \
    && ${CONDA_DIR}/bin/mamba install -n ${CONDA_ENV} -y -c conda-forge \
    'numpy<2' \
    netcdf4 \
    udunits2 \
    cython \
    websockify \
    jupyterlab \
    jupyterhub \
    awscli

# Activate conda environment by default by prepending the correct executable
ENV NB_PYTHON_PREFIX=${CONDA_DIR}/envs/${CONDA_ENV}
ENV PATH=${NB_PYTHON_PREFIX}/bin:${PATH}

# Panel Application setup
COPY dist/hefs_fews_hub-0.3.1-py3-none-any.whl hefs_fews_hub-0.3.1-py3-none-any.whl
# Install HEFS FEWS Hub with TEEHR dependency
# RUN --mount=type=cache,target=/root/.cache/pip \
RUN ${NB_PYTHON_PREFIX}/bin/pip install hefs_fews_hub-0.3.1-py3-none-any.whl \
    && rm hefs_fews_hub-0.3.1-py3-none-any.whl

# ===========================================================
# TurboVNC (https://github.com/TurboVNC/turbovnc)
# ===========================================================
ARG TURBOVNC_VERSION=3.1
# COPY libs/turbovnc-3.1.x86_64.rpm turbovnc.rpm
RUN echo "installing TurboVNC..."
RUN wget -q "https://sourceforge.net/projects/turbovnc/files/${TURBOVNC_VERSION}/turbovnc-${TURBOVNC_VERSION}.x86_64.rpm/download" -O turbovnc.rpm \
    && dnf install -y turbovnc.rpm \
    && rm turbovnc.rpm \
    && ln -s /opt/TurboVNC/bin/* /usr/local/bin/

# Override the default xstartup script with one that works for XFCE on AlmaLinux
# RUN echo '#!/bin/sh' > ${NB_PYTHON_PREFIX}/lib/python3.12/site-packages/jupyter_remote_desktop_proxy/share/xstartup \
#     && echo '' >> ${NB_PYTHON_PREFIX}/lib/python3.12/site-packages/jupyter_remote_desktop_proxy/share/xstartup \
#     && echo '# Ensure DISPLAY is set (should be passed by vncserver)' >> ${NB_PYTHON_PREFIX}/lib/python3.12/site-packages/jupyter_remote_desktop_proxy/share/xstartup \
#     && echo 'if [ -z "$DISPLAY" ]; then' >> ${NB_PYTHON_PREFIX}/lib/python3.12/site-packages/jupyter_remote_desktop_proxy/share/xstartup \
#     && echo '    export DISPLAY=:1' >> ${NB_PYTHON_PREFIX}/lib/python3.12/site-packages/jupyter_remote_desktop_proxy/share/xstartup \
#     && echo 'fi' >> ${NB_PYTHON_PREFIX}/lib/python3.12/site-packages/jupyter_remote_desktop_proxy/share/xstartup \
#     && echo '' >> ${NB_PYTHON_PREFIX}/lib/python3.12/site-packages/jupyter_remote_desktop_proxy/share/xstartup \
#     && echo 'unset SESSION_MANAGER' >> ${NB_PYTHON_PREFIX}/lib/python3.12/site-packages/jupyter_remote_desktop_proxy/share/xstartup \
#     && echo 'unset DBUS_SESSION_BUS_ADDRESS' >> ${NB_PYTHON_PREFIX}/lib/python3.12/site-packages/jupyter_remote_desktop_proxy/share/xstartup \
#     && echo '' >> ${NB_PYTHON_PREFIX}/lib/python3.12/site-packages/jupyter_remote_desktop_proxy/share/xstartup \
#     && echo '# Give X server a moment to initialize' >> ${NB_PYTHON_PREFIX}/lib/python3.12/site-packages/jupyter_remote_desktop_proxy/share/xstartup \
#     && echo 'sleep 1' >> ${NB_PYTHON_PREFIX}/lib/python3.12/site-packages/jupyter_remote_desktop_proxy/share/xstartup \
#     && echo '' >> ${NB_PYTHON_PREFIX}/lib/python3.12/site-packages/jupyter_remote_desktop_proxy/share/xstartup \
#     && echo 'exec /usr/bin/xfce4-session' >> ${NB_PYTHON_PREFIX}/lib/python3.12/site-packages/jupyter_remote_desktop_proxy/share/xstartup \
#     && chmod +x ${NB_PYTHON_PREFIX}/lib/python3.12/site-packages/jupyter_remote_desktop_proxy/share/xstartup

# Setup VNC for jovyan user (jupyter-remote-desktop-proxy will use this)
RUN mkdir -p /home/${NB_USER}/.vnc \
    && echo '#!/bin/bash' > /home/${NB_USER}/.vnc/xstartup.turbovnc \
    && echo 'unset SESSION_MANAGER' >> /home/${NB_USER}/.vnc/xstartup.turbovnc \
    && echo 'unset DBUS_SESSION_BUS_ADDRESS' >> /home/${NB_USER}/.vnc/xstartup.turbovnc \
    && echo 'export XDG_SESSION_TYPE=x11' >> /home/${NB_USER}/.vnc/xstartup.turbovnc \
    && echo 'export XDG_CURRENT_DESKTOP=XFCE' >> /home/${NB_USER}/.vnc/xstartup.turbovnc \
    && echo '# Start XFCE session with dbus' >> /home/${NB_USER}/.vnc/xstartup.turbovnc \
    && echo 'exec dbus-launch --exit-with-session startxfce4' >> /home/${NB_USER}/.vnc/xstartup.turbovnc \
    && chmod +x /home/${NB_USER}/.vnc/xstartup.turbovnc \
    && chown -R ${NB_USER}:${NB_GID} /home/${NB_USER}/.vnc

# Disable xfce-polkit autostart if it exists (it may come as a dependency)
RUN mkdir -p /home/${NB_USER}/.config/autostart \
    && echo '[Desktop Entry]' > /home/${NB_USER}/.config/autostart/xfce-polkit.desktop \
    && echo 'Hidden=true' >> /home/${NB_USER}/.config/autostart/xfce-polkit.desktop \
    && chown -R ${NB_USER}:${NB_GID} /home/${NB_USER}/.config

# ===========================================================
# FEWS
# ===========================================================
# Copy in FEWS binaries from local directory and unzip
ARG FEWS_VERSION=fews-NA-202202-127109-bin.zip
COPY --chown=${NB_USER}:${NB_GID} libs/fews/${FEWS_VERSION} /opt/fews/${FEWS_VERSION}

RUN mkdir -p /opt/fews \
    && chown ${NB_USER}:${NB_GID} /opt/fews \
    && su ${NB_USER} -c "unzip /opt/fews/${FEWS_VERSION} -d /opt/fews/" \
    && rm /opt/fews/${FEWS_VERSION} \
    && rm -rf /opt/fews/windows \
    && chmod +x /opt/fews/linux/jre/bin/java

# Install Node.js and npm
RUN curl -sL https://rpm.nodesource.com/setup_20.x | bash - \
    && dnf install -y nodejs \
    && npm install -g npm@7.24.0

# ===========================================================
# NGEN Build Dependencies
# ===========================================================
# Install all packages required to compile NGEN, its BMI modules,
# and optionally the Fortran modules (Noah-OWP, SAC-SMA, Snow-17)
# and the t-route Python routing packages.
# The actual NGEN source build is NOT done here — it is performed
# manually inside the running container by running install_ngen.sh.
#
# PowerTools (crb) is already enabled earlier for EPEL; re-enable here
# in case this layer is built independently.
RUN --mount=type=cache,target=/var/cache/dnf \
    dnf install -y epel-release && \
    (dnf config-manager --set-enabled powertools 2>/dev/null || \
     dnf config-manager --set-enabled crb 2>/dev/null || true) && \
    dnf install -y \
      gcc gcc-c++ gcc-gfortran make cmake git \
      boost-devel \
      netcdf-devel netcdf-fortran-devel hdf5-devel \
      #netcdf-devel netcdf-fortran-devel netcdf-cxx-devel netcdf-cxx4-mpich-devel hdf5-devel \
      mpich-devel \
      udunits2-devel expat-devel \
      openblas-devel sqlite-devel zlib-devel \
      python3-devel python3-pip \
      flex bison which&& \
    dnf clean all

# Create the default NGEN install root, writable by jovyan so the
# runtime install never requires sudo.
RUN mkdir -p /opt/ngen && chown ${NB_UID}:${NB_GID} /opt/ngen

# Copy NGEN installer script and make it executable from anywhere in PATH
COPY scripts/install_ngen.sh /usr/local/bin/install_ngen.sh
RUN chmod ugo+wx /usr/local/bin/install_ngen.sh

# Copy entrypoint script for AWS configuration
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER ${NB_USER}
WORKDIR /home/jovyan

EXPOSE 8888
# Set entrypoint to handle AWS configuration
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
