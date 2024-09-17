# This Dockerfile aims to provide a Pangeo-style image with the VNC/Linux Desktop feature
# It was constructed by following the instructions and copying code snippets laid out
# and linked from here:
# https://github.com/2i2c-org/infrastructure/issues/1444#issuecomment-1187405324

FROM pangeo/pangeo-notebook:2024.03.13
# FROM pangeo/base-notebook:latest

USER root
ENV DEBIAN_FRONTEND=noninteractive
ENV PATH ${NB_PYTHON_PREFIX}/bin:$PATH

# Needed for apt-key to work
RUN apt-get update -qq --yes > /dev/null && \
    apt-get install --yes -qq gnupg2 > /dev/null && \
    rm -rf /var/lib/apt/lists/*

RUN apt-get -y update \
 && apt-get install -y dbus-x11 \
   firefox \
   xfce4 \
   xfce4-panel \
   xfce4-session \
   xfce4-settings \
   xorg \
   xubuntu-icon-theme \
   curl \
 && rm -rf /var/lib/apt/lists/*

# Install Node.js and npm
RUN curl -sL https://deb.nodesource.com/setup_16.x | bash - \
    && apt-get install -y nodejs

# Install TurboVNC (https://github.com/TurboVNC/turbovnc)
ARG TURBOVNC_VERSION=2.2.6
RUN wget -q "https://sourceforge.net/projects/turbovnc/files/${TURBOVNC_VERSION}/turbovnc_${TURBOVNC_VERSION}_amd64.deb/download" -O turbovnc.deb \
 && apt-get update -qq --yes > /dev/null \
 && apt-get install -y ./turbovnc.deb > /dev/null \
 # remove light-locker to prevent screen lock
 && apt-get remove -y light-locker > /dev/null \
 && rm ./turbovnc.deb \
 && ln -s /opt/TurboVNC/bin/* /usr/local/bin/ \
 && rm -rf /var/lib/apt/lists/*

RUN mamba install -n ${CONDA_ENV} -y websockify voila

# Install jupyter-remote-desktop-proxy with compatible npm version
RUN export PATH=${NB_PYTHON_PREFIX}/bin:${PATH} \
 && npm install -g npm@7.24.0 \
 && pip install --no-cache-dir \
        https://github.com/jupyterhub/jupyter-remote-desktop-proxy/archive/main.zip


# # Download FEWS binaries from s3
# RUN aws s3 cp s3://ciroh-rti-hefs-data/fews-NA-202102-115469-bin.zip /opt/fews/fews-NA-202102-115469-bin.zip
# RUN unzip /opt/fews/fews-NA-202102-115469-bin.zip -d /opt/fews/
# RUN chmod -R 777 /opt/fews

# Copy in FEWS binaries from local directory
COPY fews/fews-NA-202102-115469-bin.zip /opt/fews/fews-NA-202102-115469-bin.zip
RUN unzip /opt/fews/fews-NA-202102-115469-bin.zip -d /opt/fews/
RUN chmod -R 777 /opt/fews

# RUN rm /opt/fews/fews-NA-202102-115469-bin.zip
# COPY fews-NA-202102-125264-patch.jar /opt/fews/fews-NA-202102-125264-patch.jar
# RUN mkdir /opt/fews

# Copy in the python notebook and scripts
COPY scripts/dashboard.ipynb .
COPY scripts/dashboard_funcs.py .

# Copy in dashboard stuff
RUN mkdir Desktop
COPY scripts/start_dashboard.sh Desktop/start_dashboard.sh
COPY scripts/dashboard.desktop Desktop/dashboard.desktop
RUN chmod -R 777 Desktop

COPY firefox/firefox-130.0.tar.bz2 Downloads/firefox-130.0.tar.bz2
RUN tar xjf Downloads/firefox-*.tar.bz2
RUN mv firefox /opt
RUN ln -s /opt/firefox/firefox /usr/local/bin/firefox
RUN rm -r .cache

# INSTALL TEEHR FROM GITHUB?

USER ${NB_USER}

WORKDIR /home/jovyan
