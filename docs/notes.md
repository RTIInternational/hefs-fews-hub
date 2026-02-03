# Development Notes and Architecture

## Architecture and Concepts

### Container Image Architecture

The HEFS-FEWS Hub container image is designed to provide a seamless environment for hydrologic ensemble forecasting and analysis, supporting both interactive Python workflows and the execution of the FEWS standalone application.

- **Operating System:**
  - The image is based on AlmaLinux 8.10, a Red Hat-compatible distribution. This was chosen because FEWS officially supports Red Hat-based systems, ensuring compatibility and stability for the FEWS binaries.

- **JupyterLab Setup:**
  - Miniconda is installed and used to create a dedicated Python environment for JupyterLab and related tools.
  - JupyterLab serves as the main user interface, providing access to a panel application for downloading FEWS configurations/data and an entrypoint for the desktop environment.

- **XFCE and VNC Desktop Environment:**
  - A minimal XFCE desktop environment is installed, offering a lightweight graphical interface for executing FEWS.
  - TurboVNC is used to enable remote desktop access, allowing users to interact with the desktop environment through their browser.
  - This setup allows users to launch and interact with the FEWS standalone application in a familiar desktop environment, directly from the cloud.

- **Additional Features:**
  - The image includes AWS CLI for data access, Node.js for JupyterLab extensions, and other utilities (e.g. nano, Thunar file manager).
  - FEWS binaries and dashboard tools are pre-installed. Desktop shortcuts are added automatically when FEWS configurations are "installed".

### AWS Credentials and S3 Access

To enable access to the S3 bucket for downloading and managing River Forecast Center configurations, you must set up a `.env` file in the project root:

1. Copy `.env.example` to `.env`:
  ```bash
  cp .env.example .env
  ```
2. Fill in your AWS credentials (`AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, and optionally `AWS_SESSION_TOKEN` for temporary credentials) in the `.env` file.

When you start the container (e.g., via Docker Compose), these credentials are automatically loaded and used to configure the AWS CLI inside the container. This enables authenticated access to the S3 bucket for data operations.

[See here](#authentication-with-your-aws-credentials) how to configure the aws cli locally for execution on the host.

### hefs_fews_hub Package Integration

The `hefs_fews_hub` Python package is responsible for installing all required dependencies and integrating the interactive application for RFC configuration management into the JupyterLab environment. This is achieved through the following mechanisms:

- **Dependency Installation:**
  - The package specifies all runtime dependencies (e.g., `panel`, `ipyleaflet`, `s3fs`, `ipywidgets`, `jupyter-server-proxy`, etc.) in its `pyproject.toml` file. These are installed automatically when the package is installed via pip or poetry, ensuring a consistent environment for the application.

- **Jupyter Server Proxy Configuration:**
  - The package provides a plugin for `jupyter-server-proxy` via the `[tool.poetry.plugins."jupyter_serverproxy_servers"]` entry in `pyproject.toml`.
  - The entry point `panel-dashboard = "hefs_fews_hub.jupyter_server_proxy_config:setup_panel_dashboard"` registers a function that configures the proxy to launch the Panel-based application as a web service accessible from JupyterLab.
  - This setup allows users to start the application from the JupyterLab launcher, providing a seamless integration between the Jupyter environment and the interactive tool for managing and downloading RFC configurations.

- **Launcher Entry:**
  - The server proxy configuration ensures that a launcher entry appears in the JupyterLab interface, enabling users to start the application with a single click. The entry is defined by the plugin and can include custom icons and labels.

## Local Development

The repository includes a docker compose file for convenience. It describes the `hefs-hub` service which uses a locally built docker image and defines: 

- Build instructions
- The correct `jupyter lab` command to start JupyterLab it the container [see Manual Docker Commands](#manual-docker-commands).
- A volume mount definition to persist the user's home folder.
  
### Persisting 

**IMPORTANT:** Docker will automatically create the `.user_home` folder in the development workspace but by default `root` will be the file owner. This ownership transfers to the mount point in the container image and the `jovyan` user, which we use in the container, wont have write access. 

Hence, if you see permission errors at container startup (from the entrypoint script), Change the ownership of `.user_home` on your host to match the container user:
```bash
sudo chown 1000:100 .user_home
```

### Using AWS CLI to copy files to/from the s3 bucket
An AWS s3 bucket was created: `ciroh-rti-hefs-data`. Read permissions are publicly available however you will need special credentials to write to the bucket.


### Using Docker Compose (recommended)

```bash
# Build and start JupyterLab with integrated remote desktop (run as background process with -d)
docker compose up --build -d

# Access JupyterLab at: http://localhost:8888
# Access the remote desktop via JupyterLab: http://localhost:8888/desktop
# (Click "Desktop" icon in JupyterLab launcher)

# Stop services
docker compose down
```

### Manual Docker Commands
From the repo root:
```bash
DOCKER_BUILDKIT=1 docker build -t hefs-hub .

# Run JupyterLab (includes integrated remote desktop via jupyter-remote-desktop-proxy)
docker run -it --rm -p 8888:8888 hefs-hub:latest \
  jupyter lab --ip=0.0.0.0 --port=8888 --no-browser \
  --NotebookApp.token='' --NotebookApp.password=''

# For interactive shell access
docker run -it --rm -p 8888:8888 hefs-hub:latest /bin/bash
```

You can pass in your AWS credentials for local testing as well during the docker build:
```bash
docker build  --build-arg AWS_ACCESS_KEY_ID="..." --build-arg AWS_SECRET_ACCESS_KEY="..."  -t hefs-hub .
```

## Execution on Development Host

### Authentication with your AWS credentials:

In your terminal run:
```bash
aws configure
```

You will see prompts like:
```bash
AWS Access Key ID [None]:
AWS Secret Access Key [None]:
Default region name [None]:
Default output format [None]:
```
Enter your access key, secret access key and `us-east-2` for region name. Hit enter to accept the default (None) value for output format.

Now you should have access to the s3 bucket using AWS CLI.

### Copying data to/from the s3 bucket
To list data in the s3 bucket:
```bash
aws s3 ls ciroh-rti-hefs-data
```

To copy a local file to the bucket:
```bash
aws s3 cp <local_filename> s3://ciroh-rti-hefs-data/<remote_filename>
```

To recursively copy a local directory to s3:
```bash
aws s3 cp <path to local dir> s3://ciroh-rti-hefs-data/ --recursive
```

To download s3 objects to local:
```bash
aws s3 cp s3://ciroh-rti-hefs-data/<remote_filename> <local_filename>
```

More details are listed here: [AWS CLI cp Reference](https://docs.aws.amazon.com/cli/latest/reference/s3/cp.html)

```bash
export BOKEH_ALLOW_WS_ORIGIN=*
export BOKEH_LOG_LEVEL=debug
export BOKEH_PY_LOG_LEVEL=debug 
export PANEL_LOG_LEVEL=debug
jupyter lab --ip=0.0.0.0 --port=8888 --no-browser --NotebookApp.token='' --NotebookApp.password='' --allow-root --log-level=DEBUG
```

## Push a new tag to build and push a new Docker image
Pushing the tag triggers the `docker_publish.yml` github action workflow to run automatically. After merging your changes to `main`:
```bash
git checkout main
git pull
git tag -a v0.x.x -m "version 0.x.x"
git push origin v0.x.x
```

## Push a new tag to build and push a new Docker image
Pushing the tag triggers the `docker_publish.yml` github action workflow to run automatically. After merging your changes to `main`: