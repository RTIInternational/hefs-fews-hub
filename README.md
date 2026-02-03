# Container Image Overview

Provides the HEFS-FEWS Hub container image, designed for use on TEEHRHub and similar JupyterHub deployments, to support the exploration of HEFS ensembles using FEWS. Part of a CIROH-supported project.

The image is based on AlmaLinux 8.10 (chosen for official FEWS support), and includes:
- **JupyterLab** for interactive Python development and dashboarding
- **XFCE desktop environment** and **TurboVNC** for a full-featured remote desktop, allowing users to run FEWS in a graphical environment
- Pre-installed FEWS binaries, and AWS CLI for data access
- The `hefs-fews-hub` python package (also part of this repository)

This setup enables users to analyze hydrologic ensemble forecasts and interact with FEWS in a cloud-hosted desktop environment.

**Warning! This is currently highly experimental!**

## Signing in to HEFS-FEWS at TEEHR-Hub
1. Go to `https://teehr-hub.rtiamanzi.org/hub/spawn`
2. Sign in with your github account (you'll need to create one if you don't have it)
3. From the list, select `HEFS-FEWS Evaluation System`. Click `Start`
4. When JupyterHub starts, Go to Desktop
5. The first time you login, open the terminal in the Desktop and run `cp /opt/hefs_fews_dashboard/dashboard.desktop .`  This will create a desktop icon to start the dashboard.  You should only need to do this once.
6. Select the RFC you wish to work with
7. Specify a directory path. Data downloaded to the `/home/jovyan` directory will persist between sessions.
8. After downloading the configuration, click the FEWS icon to start FEWS.

Things to watch out for:
* If the remote desktop is idle for too long, you may get logged out and may need to restart TEEHRHub!




### TODO: Selecting and configuring your FEWS standalone [WIP]

Dashboard approach:
1. Start up TEEHRHub
2. Select appropriate image
3. Go to Remote Desktop
4. Click on "Launch" icon to launch dashboard
5. Select the desired standalone
6. Click `Configure Standalone` button
7. Double-click the FEWS desktop icon when it appears

OR, Notebook approach:
1. Run the notebook `dashboard.ipynb`
2. Follow steps 5-7 above