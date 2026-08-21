# syntax=docker/dockerfile:1

# ===========================================================
# STAGE 1: Shared Base Runtime (AlmaLinux 8.10)
# ===========================================================
FROM almalinux:8.10 AS base
USER root

ENV TROUTE_REPO=CIROH-UA/t-route
ENV TROUTE_BRANCH=ngiab
ENV NGEN_REPO=CIROH-UA/ngen
ENV NGEN_BRANCH=ngiab

RUN --mount=type=cache,target=/var/cache/dnf \
    dnf install -y epel-release && \
    dnf config-manager --set-enabled powertools && \
    dnf install -y \
    vim libgfortran sqlite \
    bzip2 expat udunits2 zlib \
    mpich hdf5 netcdf netcdf-fortran netcdf-cxx netcdf-cxx4-mpich \
    openblas python3.11

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
    sudo gcc gcc-c++ make cmake tar git gcc-gfortran sqlite-devel \
    python3.11-devel python3.11-pip \
    expat-devel flex bison udunits2-devel zlib-devel \
    wget mpich-devel hdf5-devel netcdf-devel \
    netcdf-fortran-devel netcdf-cxx-devel lld clang \
    openblas-devel unzip gcc-toolset-13-gcc-gfortran
# AlmaLinux 8 ships ninja 1.8.2; Fortran support requires 1.10+
RUN wget -q https://github.com/ninja-build/ninja/releases/download/v1.11.1/ninja-linux.zip && \
    unzip ninja-linux.zip -d /usr/local/bin && \
    rm ninja-linux.zip
RUN python3.11 -m pip install "numpy<2.0"
# Use GCC 13 gfortran to fix preprocessor apostrophe-in-comment bug in gfortran 8.x #???
ENV PATH="/opt/rh/gcc-toolset-13/root/usr/bin:${PATH}" 

# ===========================================================
# STAGE 3: NGEN Dependency Compilations (Boost, T-Route, NGEN)
# ===========================================================
FROM build_base AS boost_build
RUN wget https://archives.boost.io/release/1.86.0/source/boost_1_86_0.tar.gz && \
    tar -xzf boost_1_86_0.tar.gz && \
    cd boost_1_86_0 && ./bootstrap.sh && ./b2 headers
ENV BOOST_ROOT=/boost_1_86_0

FROM boost_build AS troute_prebuild
WORKDIR /ngen
ENV FC=gfortran NETCDF=/usr/lib64/gfortran/modules/
RUN ln -s /usr/bin/python3.11 /usr/bin/python || true
RUN uv venv -p 3.11
ENV PATH="/ngen/.venv/bin:$PATH"
ADD https://api.github.com/repos/${TROUTE_REPO}/git/refs/heads/${TROUTE_BRANCH} /tmp/version.json
RUN uv pip install -r https://raw.githubusercontent.com/$TROUTE_REPO/refs/heads/$TROUTE_BRANCH/requirements.txt

FROM troute_prebuild AS troute_build
WORKDIR /ngen/t-route
RUN git clone --depth 1 --single-branch --branch $TROUTE_BRANCH https://github.com/$TROUTE_REPO.git . && \
    git submodule update --init --depth 1 && \
    uv pip install build wheel && \
    sed -i 's/build_[a-z]*=/#&/' compiler.sh && \
    ./compiler.sh no-e && \
    uv pip install --config-setting='--build-option=--use-cython' src/troute-network/ && \
    uv build --wheel --config-setting='--build-option=--use-cython' src/troute-network/ && \
    uv pip install --no-build-isolation --config-setting='--build-option=--use-cython' src/troute-routing/ && \
    uv build --wheel --no-build-isolation --config-setting='--build-option=--use-cython' src/troute-routing/ && \
    uv build --wheel --no-build-isolation src/troute-config/ && \
    uv build --wheel --no-build-isolation src/troute-nwm/ && \
    mkdir /wheels && cp /ngen/t-route/src/troute-*/dist/*.whl /wheels/

FROM boost_build AS ngen_clone
WORKDIR /ngen
ADD https://api.github.com/repos/${NGEN_REPO}/git/refs/heads/${NGEN_BRANCH} /tmp/version.json
RUN git clone --single-branch --branch $NGEN_BRANCH https://github.com/$NGEN_REPO.git && \
    cd ngen && \
    git submodule update --init --recursive --depth 1

FROM ngen_clone AS ngen_build
ENV PATH=${PATH}:/usr/lib64/mpich/bin
WORKDIR /ngen/ngen
ARG COMMON_BUILD_ARGS="-DNGEN_WITH_EXTERN_ALL=ON -DNGEN_WITH_NETCDF:BOOL=ON -DNGEN_WITH_BMI_C:BOOL=ON -DNGEN_WITH_BMI_FORTRAN:BOOL=ON -DNGEN_WITH_PYTHON:BOOL=ON -DNGEN_WITH_ROUTING:BOOL=ON -DNGEN_WITH_SQLITE:BOOL=ON -DNGEN_WITH_UDUNITS:BOOL=ON -DUDUNITS_QUIET:BOOL=ON -DNGEN_WITH_TESTS:BOOL=OFF -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=. -DCMAKE_CXX_FLAGS='-fuse-ld=lld' -DPython_EXECUTABLE=/usr/bin/python3.11"
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
    cmake -G Ninja -B build_sundials sundials-${SUNDIALS_VERSION} -DEXAMPLES_ENABLE_C=OFF -DEXAMPLES_ENABLE_F2003=OFF -DBUILD_FORTRAN_MODULE_INTERFACE=ON -DCMAKE_Fortran_COMPILER=gfortran -DCMAKE_INSTALL_PREFIX=/sundials/install && \
    cmake --build build_sundials --target all -- -j $(nproc) && \
    cmake --build build_sundials --target install

FROM build_sundials AS build_summa
WORKDIR /ngen/ngen/extern/summa
RUN cmake -G Ninja -B build_summa -DUSE_NEXTGEN=ON -DUSE_SUNDIALS=ON -DSPECIFY_LAPACK_LINKS=OFF -DCMAKE_BUILD_TYPE=Release -DNetCDF_F90_INCLUDE_DIR=/usr/lib64/gfortran/modules/ -DOpenBLAS_INCLUDE_DIR=/usr/include/openblas -DSUNDIALS_DIR=/sundials/build_sundials/ -DCMAKE_Fortran_COMPILER=gfortran && \
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
FROM almalinux:8.10 AS final
USER root

# HEFS-FEWS-Hub OS Dependencies
RUN --mount=type=cache,id=final-dnf,target=/var/cache/dnf \
    dnf install epel-release -y && \
    dnf config-manager --set-enabled powertools

    # add udunits in here?
RUN --mount=type=cache,id=final-dnf,target=/var/cache/dnf \
    dnf install -y --enablerepo=epel \
    dpkg dbus-x11 xfce4-session xfce4-panel xfce4-settings xfdesktop xfwm4 xfce4-terminal \
    featherpad nano Thunar xorg-x11-server-Xorg xorg-x11-xinit xorg-x11-xauth xorg-x11-fonts-* \
    xorg-x11-utils curl wget git-lfs perl unzip mpich hdf5 netcdf netcdf-fortran netcdf-cxx netcdf-cxx4-mpich \
    python3.11-devel python3.11-pip udunits2
RUN dnf clean all
RUN python3.11 -m pip install "numpy<2.0"

RUN wget https://repo.almalinux.org/almalinux/8/AppStream/x86_64/os/Packages/compat-libgfortran-48-4.8.5-36.1.el8.i686.rpm && \
    dpkg --add-architecture i386 && \
    dnf -y install compat-libgfortran-48-4.8.5-36.1.el8.i686.rpm libstdc++.i686 glibc.i686 && \
    rm compat-libgfortran-48-4.8.5-36.1.el8.i686.rpm

ENV CONDA_ENV=notebook \
    NB_USER=jovyan \
    NB_UID=1000 \
    NB_GID=100 \
    CONDA_DIR=/opt/conda \
    SHELL=/bin/bash \
    TZ=UTC

RUN echo ". ${CONDA_DIR}/etc/profile.d/conda.sh ; conda activate ${CONDA_ENV}" > /etc/profile.d/init_conda.sh
RUN groupadd -g ${NB_GID} ${NB_USER} || true && useradd -m -s /bin/bash -u ${NB_UID} -g ${NB_GID} ${NB_USER}

ENV PATH=${CONDA_DIR}/bin:${PATH}
RUN chown -R ${NB_USER}:${NB_GID} /opt/

RUN echo "Installing Miniforge..." && \
    URL="https://github.com/conda-forge/miniforge/releases/latest/download/Miniforge3-Linux-$(uname -m).sh" && \
    wget --quiet ${URL} -O installer.sh && \
    /bin/bash installer.sh -u -b -p ${CONDA_DIR} && \
    rm installer.sh && \
    ${CONDA_DIR}/bin/mamba clean -afy && \
    find ${CONDA_DIR} -follow -type f -name '*.a' -delete

RUN --mount=type=cache,target=/opt/conda/pkgs \
    ${CONDA_DIR}/bin/mamba create -n ${CONDA_ENV} -y python=3.12 && \
    ${CONDA_DIR}/bin/mamba install -n ${CONDA_ENV} -y -c conda-forge websockify jupyterlab jupyterhub awscli

ENV NB_PYTHON_PREFIX=${CONDA_DIR}/envs/${CONDA_ENV}
ENV PATH=${NB_PYTHON_PREFIX}/bin:${PATH}

COPY dist/hefs_fews_hub-0.3.1-py3-none-any.whl hefs_fews_hub-0.3.1-py3-none-any.whl
RUN ${NB_PYTHON_PREFIX}/bin/pip install hefs_fews_hub-0.3.1-py3-none-any.whl && rm hefs_fews_hub-0.3.1-py3-none-any.whl

# TurboVNC Setup
ARG TURBOVNC_VERSION=3.1
RUN wget -q "https://sourceforge.net/projects/turbovnc/files/${TURBOVNC_VERSION}/turbovnc-${TURBOVNC_VERSION}.x86_64.rpm/download" -O turbovnc.rpm && \
    dnf install -y turbovnc.rpm && rm turbovnc.rpm && ln -s /opt/TurboVNC/bin/* /usr/local/bin/

RUN mkdir -p /home/${NB_USER}/.vnc && \
    echo '#!/bin/bash' > /home/${NB_USER}/.vnc/xstartup.turbovnc && \
    echo 'unset SESSION_MANAGER' >> /home/${NB_USER}/.vnc/xstartup.turbovnc && \
    echo 'unset DBUS_SESSION_BUS_ADDRESS' >> /home/${NB_USER}/.vnc/xstartup.turbovnc && \
    echo 'export XDG_SESSION_TYPE=x11' >> /home/${NB_USER}/.vnc/xstartup.turbovnc && \
    echo 'export XDG_CURRENT_DESKTOP=XFCE' >> /home/${NB_USER}/.vnc/xstartup.turbovnc && \
    echo 'exec dbus-launch --exit-with-session startxfce4' >> /home/${NB_USER}/.vnc/xstartup.turbovnc && \
    chmod +x /home/${NB_USER}/.vnc/xstartup.turbovnc && \
    chown -R ${NB_USER}:${NB_GID} /home/${NB_USER}/.vnc

RUN mkdir -p /home/${NB_USER}/.config/autostart && \
    echo '[Desktop Entry]' > /home/${NB_USER}/.config/autostart/xfce-polkit.desktop && \
    echo 'Hidden=true' >> /home/${NB_USER}/.config/autostart/xfce-polkit.desktop && \
    chown -R ${NB_USER}:${NB_GID} /home/${NB_USER}/.config

# FEWS Binary Setup
ARG FEWS_VERSION=fews-NA-202202-127109-bin.zip
COPY --chown=${NB_USER}:${NB_GID} libs/fews/${FEWS_VERSION} /opt/fews/${FEWS_VERSION}
RUN mkdir -p /opt/fews && \
    chown ${NB_USER}:${NB_GID} /opt/fews && \
    su ${NB_USER} -c "unzip /opt/fews/${FEWS_VERSION} -d /opt/fews/" && \
    rm /opt/fews/${FEWS_VERSION} && rm -rf /opt/fews/windows && \
    chmod +x /opt/fews/linux/jre/bin/java

RUN curl -sL https://rpm.nodesource.com/setup_20.x | bash - && \
    dnf install -y nodejs && npm install -g npm@7.24.0

COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

# ===========================================================
# INJECT COMPILED NGEN ARTIFACTS
# ===========================================================
COPY --from=restructure_files /dmod /dmod
COPY --from=build_sundials /sundials/install/ /sundials

RUN ln -s /dmod/bin/ngen /usr/local/bin/ngen && \
    echo "/dmod/shared_libs/" >> /etc/ld.so.conf.d/ngen.conf && \
    echo "/sundials/lib64" >> /etc/ld.so.conf.d/sundials.conf && \
    ldconfig -v

ENV PATH=$PATH:/usr/lib64/mpich/bin

USER ${NB_USER}
WORKDIR /home/jovyan

EXPOSE 8888
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]