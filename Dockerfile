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

FROM almalinux:8.10
# FROM 935462133478.dkr.ecr.us-east-2.amazonaws.com/teehr:v0.4-beta

USER root
# Install EPEL repository for additional packages
RUN --mount=type=cache,target=/var/cache/dnf \
    dnf install epel-release -y

# Install XFCE components individually to save space
RUN --mount=type=cache,target=/var/cache/dnf \
    dnf install -y --enablerepo=epel \
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
    unzip && \
    dnf clean all

# Install TurboVNC (https://github.com/TurboVNC/turbovnc)
# ARG TURBOVNC_VERSION=3.1
RUN wget -q "https://sourceforge.net/projects/turbovnc/files/${TURBOVNC_VERSION}/turbovnc-${TURBOVNC_VERSION}.x86_64.rpm/download" -O turbovnc.rpm \
# COPY libs/turbovnc-3.1.x86_64.rpm turbovnc.rpm
RUN dnf install -y turbovnc.rpm \
    && rm turbovnc.rpm \
    && ln -s /opt/TurboVNC/bin/* /usr/local/bin/

# Install Miniconda (for mamba/conda)
ENV CONDA_DIR=/opt/conda
ENV PATH=${CONDA_DIR}/bin:${PATH}
RUN --mount=type=cache,target=/root/.conda/pkgs \
    wget -q https://repo.anaconda.com/miniconda/Miniconda3-latest-Linux-x86_64.sh -O /tmp/miniconda.sh \
    && bash /tmp/miniconda.sh -b -p ${CONDA_DIR} \
    && rm /tmp/miniconda.sh \
    && conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/main \
    && conda tos accept --override-channels --channel https://repo.anaconda.com/pkgs/r

# Create conda environment and install packages
ENV CONDA_ENV=notebook
RUN --mount=type=cache,target=/root/.conda/pkgs \
    conda create -n ${CONDA_ENV} -y python=3.11 \
    && conda install -n ${CONDA_ENV} -y -c conda-forge \
    websockify \
    jupyterlab \
    awscli

# Activate conda environment by default
ENV NB_PYTHON_PREFIX=${CONDA_DIR}/envs/${CONDA_ENV}
ENV PATH=${NB_PYTHON_PREFIX}/bin:${PATH}
# Install Node.js and npm
RUN curl -sL https://rpm.nodesource.com/setup_20.x | bash - \
    && dnf install -y nodejs \
    && npm install -g npm@7.24.0
    
    # Create jovyan user
ARG NB_USER=jovyan
ARG NB_UID=1000
ARG NB_GID=100
RUN groupadd -g ${NB_GID} ${NB_USER} || true \
&& useradd -m -s /bin/bash -u ${NB_UID} -g ${NB_GID} ${NB_USER} \
    && mkdir -p /home/${NB_USER}

# Copy in FEWS binaries from local directory
COPY libs/fews/fews-NA-202102-115469-bin.zip /opt/fews/fews-NA-202102-115469-bin.zip
RUN unzip /opt/fews/fews-NA-202102-115469-bin.zip -d /opt/fews/ \
    && chown -R ${NB_USER}:${NB_GID} /opt/ \
    && rm /opt/fews/fews-NA-202102-115469-bin.zip \
    && rm -rf /opt/fews/windows

# Panel Application setup
COPY dist/hefs_fews_hub-0.1.0-py3-none-any.whl hefs_fews_hub-0.1.0-py3-none-any.whl
# Install HEFS FEWS Hub with TEEHR dependency
# RUN --mount=type=cache,target=/root/.cache/pip \
RUN pip install hefs_fews_hub-0.1.0-py3-none-any.whl \
    && rm hefs_fews_hub-0.1.0-py3-none-any.whl

# Override the default xstartup script with one that works for XFCE on AlmaLinux
RUN echo '#!/bin/sh' > ${NB_PYTHON_PREFIX}/lib/python3.11/site-packages/jupyter_remote_desktop_proxy/share/xstartup \
    && echo '' >> ${NB_PYTHON_PREFIX}/lib/python3.11/site-packages/jupyter_remote_desktop_proxy/share/xstartup \
    && echo '# Ensure DISPLAY is set (should be passed by vncserver)' >> ${NB_PYTHON_PREFIX}/lib/python3.11/site-packages/jupyter_remote_desktop_proxy/share/xstartup \
    && echo 'if [ -z "$DISPLAY" ]; then' >> ${NB_PYTHON_PREFIX}/lib/python3.11/site-packages/jupyter_remote_desktop_proxy/share/xstartup \
    && echo '    export DISPLAY=:1' >> ${NB_PYTHON_PREFIX}/lib/python3.11/site-packages/jupyter_remote_desktop_proxy/share/xstartup \
    && echo 'fi' >> ${NB_PYTHON_PREFIX}/lib/python3.11/site-packages/jupyter_remote_desktop_proxy/share/xstartup \
    && echo '' >> ${NB_PYTHON_PREFIX}/lib/python3.11/site-packages/jupyter_remote_desktop_proxy/share/xstartup \
    && echo 'unset SESSION_MANAGER' >> ${NB_PYTHON_PREFIX}/lib/python3.11/site-packages/jupyter_remote_desktop_proxy/share/xstartup \
    && echo 'unset DBUS_SESSION_BUS_ADDRESS' >> ${NB_PYTHON_PREFIX}/lib/python3.11/site-packages/jupyter_remote_desktop_proxy/share/xstartup \
    && echo '' >> ${NB_PYTHON_PREFIX}/lib/python3.11/site-packages/jupyter_remote_desktop_proxy/share/xstartup \
    && echo '# Give X server a moment to initialize' >> ${NB_PYTHON_PREFIX}/lib/python3.11/site-packages/jupyter_remote_desktop_proxy/share/xstartup \
    && echo 'sleep 1' >> ${NB_PYTHON_PREFIX}/lib/python3.11/site-packages/jupyter_remote_desktop_proxy/share/xstartup \
    && echo '' >> ${NB_PYTHON_PREFIX}/lib/python3.11/site-packages/jupyter_remote_desktop_proxy/share/xstartup \
    && echo 'exec /usr/bin/xfce4-session' >> ${NB_PYTHON_PREFIX}/lib/python3.11/site-packages/jupyter_remote_desktop_proxy/share/xstartup \
    && chmod +x ${NB_PYTHON_PREFIX}/lib/python3.11/site-packages/jupyter_remote_desktop_proxy/share/xstartup

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

# Copy entrypoint script for AWS configuration
COPY entrypoint.sh /usr/local/bin/entrypoint.sh
RUN chmod +x /usr/local/bin/entrypoint.sh

USER ${NB_USER}

WORKDIR /home/jovyan

# Set entrypoint to handle AWS configuration
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD ["jupyter", "lab", "--ip=0.0.0.0", "--port=8888", "--no-browser", "--NotebookApp.token=", "--NotebookApp.password="]