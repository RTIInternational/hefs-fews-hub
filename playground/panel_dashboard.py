import json
from pathlib import Path

import panel as pn
from ipyleaflet import Map, GeoJSON

from dashboard_funcs import (
    create_start_standalone_command,
    write_shell_file,
    s3_download_file,
    write_fews_desktop_shortcut,
    s3_download_directory_cli,
    set_up_logger
)

pn.extension("ipywidgets", sizing_mode="stretch_width")

ACCENT_BASE_COLOR = "#5d6d7e"

RFC_BOUNDARIES = "/opt/hefs_fews_dashboard/rfc_boundaries.geojson"
FEWS_INSTALL_DIR = Path("/opt", "fews")
MAP_CENTER_X = 38.80
MAP_CENTER_Y = -99.14
BUCKET_NAME = "ciroh-rti-hefs-data"
RFC_IDS = [
    "ABRFC",
    "APRFC",
    "CBRFC",
    "CNRFC",
    "LMRFC",
    "MARFC",
    "MBRFC",
    "NCRFC",
    "NERFC",
    "NWRFC",
    "OHRFC",
    "SERFC",
    "WGRFC"
]


def turn_off_indeterminate():
    indeterminate.name = "Download Complete"
    indeterminate.active = False
    indeterminate.visible = False
    return


def turn_on_indeterminate():
    indeterminate.name = "Downloading..."
    indeterminate.visible = True
    indeterminate.active = True
    return


def on_geojson_click(event, feature, **kwargs):
    rfc_selector.value = feature['properties']["BASIN_ID"]
    return


def get_marker_and_map():
    center = (MAP_CENTER_X, MAP_CENTER_Y)
    lmap = Map(center=center, zoom=4, height=500)
    lmap.add(geojson_layer)
    lmap.layout.height = "100%"
    lmap.layout.width = "100%"
    return lmap


def download_historical_data(event) -> None:
    """Download historical data for selected RFC."""
    fews_download_dir = Path(download_dir_text.value)
    if not fews_download_dir.exists():
        raise ValueError(
            f"The directory: {fews_download_dir}, "
            "does not exist. Please create it first!"
        )

    logger.info(f"Downloading historical data to {fews_download_dir.as_posix()}...")
    s3_download_directory_cli(
        prefix=f"{rfc_selector.value}/historicalData",
        local=Path(
            fews_download_dir,
            f"{rfc_selector.value}/cardfiles"
        ).as_posix()
    )
    logger.info("Data download complete.")


def install_fews_standalone(event) -> None:
    """Download standalone configuration from S3 to the working directory."""
    turn_on_indeterminate()
    fews_download_dir = Path(download_dir_text.value)
    if not fews_download_dir.exists():
        logger.info(f"The directory: {fews_download_dir}, does not exist. Please create it first!")
        raise ValueError(f"The directory: {fews_download_dir}, does not exist. Please create it first!")

    # 1. Download sa from S3
    logger.info(f"Downloading {rfc_selector.value} configuration to {fews_download_dir.as_posix()}...This will take a few minutes...")
    s3_download_directory_cli(
        prefix=f"{rfc_selector.value}/Config",
        local=Path(fews_download_dir, f"{rfc_selector.value}/Config").as_posix(),
    )
    # 2. Create the bash command to run the standalone configuration
    logger.info("Creating bash command to start FEWS...")
    sa_dir_path = Path(fews_download_dir, rfc_selector.value)
    bash_command_str = create_start_standalone_command(
        fews_root_dir=FEWS_INSTALL_DIR.as_posix(),
        configuration_dir=sa_dir_path.as_posix()
    )
    # 3. Write the command to start FEWS to a shell script
    logger.info("Writing shell script to start FEWS...")
    shell_script_filepath = Path(sa_dir_path, "start_fews_standalone.sh")
    write_shell_file(shell_script_filepath, bash_command_str)

    # 4. Copy in patch file for the downloaded standalone config.
    logger.info("Downloading patch file and global properties...")
    s3_download_file(
        remote_filepath="fews-install/fews-NA-202102-125264-patch.jar",
        local_filepath=Path(sa_dir_path, "fews-NA-202102-125264-patch.jar")
    )
    logger.info("Downloading sa_global.properties...Temporarily to Config dir.")
    s3_download_file(
        remote_filepath=f"{rfc_selector.value}/sa_global.properties",
        local_filepath=Path(sa_dir_path, "Config", "sa_global.properties")
    )
    # 5. Create FEWS desktop shortcut that calls the shell script
    desktop_shortcut_filepath = Path(
        Path.home(),
        "Desktop",
        f"{sa_dir_path.name}.desktop"
    )
    logger.info(f"Creating FEWS desktop shortcut...{desktop_shortcut_filepath}")
    write_fews_desktop_shortcut(
        desktop_shortcut_filepath,
        shell_script_filepath,
        rfc_selector.value
    )
    turn_off_indeterminate()
    logger.info("Installation complete.")
    return


# MAP (ipyleaflet)
with open(RFC_BOUNDARIES) as f:
    geojson_data = json.load(f)

geojson_layer = GeoJSON(
    data=geojson_data,
    hover_style={
        'color': 'red', 'dashArray': '0', 'fillOpacity': 0.6
    },
)
lmap = get_marker_and_map()
geojson_layer.on_click(on_geojson_click)

# WIDGETS
rfc_selector = pn.widgets.Select(name="", options=RFC_IDS, value=RFC_IDS[5])

download_dir_text = pn.widgets.TextInput(
    name='Directory to download the data:',
    value='/home/jovyan'
)

logger_filepath = Path(download_dir_text.value, "dashboard.log")
logger = set_up_logger(logger_filepath)

download_configs_button = pn.widgets.Button(
    name='Download Configs',
    button_type='primary'
)
download_configs_button.on_click(install_fews_standalone)

download_data_button = pn.widgets.Button(
    name='Download Data',
    button_type='primary'
)
download_data_button.on_click(download_historical_data)

indeterminate = pn.indicators.Progress(
    name='Indeterminate Progress',
    active=False,
    visible=False,
    styles={"height": "15px"},
)

# LAYOUT
download_row = pn.Row(
    rfc_selector,
    download_configs_button,
    download_data_button
)

column = pn.Column(
    pn.panel(lmap, sizing_mode="stretch_both", min_height=500),
    download_row,
    pn.Row(download_dir_text),
    pn.Row(indeterminate)
)

template = pn.template.FastListTemplate(
    site="HEFS-FEWS",
    title="Exploration System Dashboard",
    logo="https://ciroh.ua.edu/wp-content/uploads/2022/08/CIROHLogo_200x200.png",
    header_background=ACCENT_BASE_COLOR,
    accent_base_color=ACCENT_BASE_COLOR,
    main=[column],
).servable()
