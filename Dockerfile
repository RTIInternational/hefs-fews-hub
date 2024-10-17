# This Dockerfile aims to provide a Pangeo-style image with the VNC/Linux Desktop feature
# It was constructed by following the instructions and copying code snippets laid out
# and linked from here:
# https://github.com/2i2c-org/infrastructure/issues/1444#issuecomment-1187405324

FROM pangeo/pangeo-notebook:2024.10.01

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
 && rm -rf /var/lib/apt/lists/* \
# Disable the automatic screenlock since the account password is unknown
 && apt-get -y -qq remove xfce4-screensaver

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

# Install TEEHR
RUN pip install 'teehr @ git+https://github.com/RTIInternational/teehr@v0.4-beta'

# Install git-lfs
RUN apt-get update && apt-get install git-lfs -y

# Install jupyter-server-proxy?

# # Download FEWS binaries from s3?
# RUN aws s3 cp s3://ciroh-rti-hefs-data/fews-NA-202102-115469-bin.zip /opt/fews/fews-NA-202102-115469-bin.zip
# RUN unzip /opt/fews/fews-NA-202102-115469-bin.zip -d /opt/fews/

# Copy in FEWS binaries from local directory
COPY fews/fews-NA-202102-115469-bin.zip /opt/fews/fews-NA-202102-115469-bin.zip
RUN unzip /opt/fews/fews-NA-202102-115469-bin.zip -d /opt/fews/ \
 && chown -R jovyan:jovyan /opt/fews

RUN mkdir /opt/data \
 && chown -R jovyan:jovyan /opt/data

# Copy in the python notebook and scripts

# IPywidgets
# COPY scripts/dashboard.ipynb scripts/dashboard_funcs.py scripts/start_dashboard.sh /opt/hefs_fews_dashboard/
# COPY images/index_getting_started.svg /opt/hefs_fews_dashboard/index_getting_started.svg
# COPY images/CIROHLogo_200x200.png /opt/hefs_fews_dashboard/CIROHLogo_200x200.png
# Panel
COPY playground/panel_dashboard.py playground/dashboard_funcs.py playground/start_dashboard.sh /opt/hefs_fews_dashboard/
COPY playground/geo/rfc_boundaries.geojson /opt/hefs_fews_dashboard/rfc_boundaries.geojson
COPY images/index_getting_started.svg /opt/hefs_fews_dashboard/index_getting_started.svg
COPY images/CIROHLogo_200x200.png /opt/hefs_fews_dashboard/CIROHLogo_200x200.png
RUN chown -R jovyan:jovyan /opt/hefs_fews_dashboard && chmod +x /opt/hefs_fews_dashboard/start_dashboard.sh
COPY playground/panel_requirements.txt /opt/hefs_fews_dashboard/
RUN pip install -r /opt/hefs_fews_dashboard/panel_requirements.txt

# Create Desktop dir and copy in the dashboard desktop file
COPY scripts/dashboard.desktop /opt/hefs_fews_dashboard/dashboard.desktop
RUN chmod +x /opt/hefs_fews_dashboard/dashboard.desktop

# Install Firefox
RUN wget -P Downloads https://ftp.mozilla.org/pub/firefox/releases/131.0b9/linux-x86_64/en-US/firefox-131.0b9.tar.bz2 \
 && tar xjf Downloads/firefox-*.tar.bz2 \
 && mv firefox /opt \
 && ln -s /opt/firefox/firefox /usr/local/bin/firefox \
 && rm -r .cache

# # For firefox??
# RUN install -d -m 0755 /etc/apt/keyrings \
#   && wget -q https://packages.mozilla.org/apt/repo-signing-key.gpg -O- | tee /etc/apt/keyrings/packages.mozilla.org.asc > /dev/null \
#   && echo "deb [signed-by=/etc/apt/keyrings/packages.mozilla.org.asc] https://packages.mozilla.org/apt mozilla main" | tee -a /etc/apt/sources.list.d/mozilla.list > /dev/null \
#   $$ echo 'Package: *Pin: origin packages.mozilla.orgPin-Priority: 1000' | tee /etc/apt/preferences.d/mozilla \
#   && apt-get update && apt-get install firefox -y

# COPY playground/jupyter-panel-proxy.yml /opt/hefs_fews_dashboard/jupyter-panel-proxy.yml
# RUN jupyter server extension enable panel.io.jupyter_server_extension

# ENV BOKEH_ALLOW_WS_ORIGIN "*"

# Run the web service on container startup.
# CMD panel serve /opt/hefs_fews_dashboard/panel_dashboard.py --allow-websocket-origin="*" --port 8888 --autoreload --address 0.0.0.0 --static-dirs

RUN aws configure set aws_access_key_id $AWS_ACCESS_KEY_ID \
 && aws configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY \
 && aws configure set default.region us-east-2

USER ${NB_USER}

WORKDIR /home/jovyan