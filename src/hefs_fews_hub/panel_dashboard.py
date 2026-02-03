# import debugpy; debugpy.listen(5678); debugpy.wait_for_client() # noqa
import contextlib
import json
from pathlib import Path
import logging
import panel as pn
from panel.pane import IPyWidget

# from ipywidgets_bokeh import IPyWidget
from hefs_fews_hub.dashboard_funcs import install_fews_standalone
from ipyleaflet import Map, GeoJSON


FORMAT = "%(asctime)s | %(levelname)s | %(name)s | %(message)s"


class PanelLogHandler(logging.Handler):
    """Custom logging handler that writes to a Panel TextAreaInput widget."""
    
    def __init__(self, text_widget):
        super().__init__()
        self.text_widget = text_widget
        
    def emit(self, record):
        """Append log message to the text widget."""
        try:
            msg = self.format(record)
            self.text_widget.value += msg + "\n"
        except Exception:
            self.handleError(record)


@pn.cache
def reconfig_basic_config(format_=FORMAT, level=logging.INFO):
    """(Re-)configure logging"""
    logging.basicConfig(format=format_, level=level, force=True)
    logging.info("Logging.basicConfig completed successfully")


with contextlib.suppress(Exception):
    from hefs_fews_hub.dashboard_funcs import s3_download_directory_cli, set_up_logger

pn.extension("ipywidgets", sizing_mode="stretch_width")

ACCENT_BASE_COLOR = "#5d6d7e"
RFC_BOUNDARIES = Path(__file__).parent / "geo" / "rfc_boundaries.geojson"
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
    "WGRFC",
]

download_dir_text = pn.widgets.TextInput(
    name="Directory to download the data:", value="/home/jovyan"
)

logger_filepath = Path(download_dir_text.value, "hefs_fews_config_panel.log")
print(f"Logging to: {logger_filepath}")
logger = set_up_logger(logger_filepath)


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
    rfc_selector.value = feature["properties"]["BASIN_ID"]


def get_marker_and_map():
    center = (MAP_CENTER_X, MAP_CENTER_Y)
    lmap = Map(center=center, zoom=4, height=500)
    lmap.add(geojson_layer)
    lmap.layout.height = "100%"
    lmap.layout.width = "100%"
    return lmap

def install_fews_standalone_pf(event) -> None:
    """Download standalone configuration from S3 to the working directory."""
    turn_on_indeterminate()
    try:
        install_fews_standalone(download_dir_text.value, rfc_selector.value)
    except Exception as e:
        logger.error(f"Error installing FEWS standalone: {e}")
    finally:
        turn_off_indeterminate()
    return


# MAP (ipyleaflet)
with open(RFC_BOUNDARIES) as f:
    geojson_data = json.load(f)

geojson_layer = GeoJSON(
    data=geojson_data,
    hover_style={"color": "red", "dashArray": "0", "fillOpacity": 0.6},
)
try:
    lmap = get_marker_and_map()
    geojson_layer.on_click(on_geojson_click)
except Exception as e:
    logger.error(f"Error creating map: {e}")
    lmap = pn.pane.Markdown(
        "## Error loading map\n"
        "Map could not be loaded. Please ensure that ipyleaflet is "
        "installed and working correctly."
    )

# WIDGETS
rfc_selector = pn.widgets.Select(name="", options=RFC_IDS, value=RFC_IDS[5])


download_configs_button = pn.widgets.Button(
    name="Download Configs", button_type="primary"
)
download_configs_button.on_click(install_fews_standalone_pf)


indeterminate = pn.indicators.Progress(
    name="Indeterminate Progress",
    active=False,
    visible=False,
    styles={"height": "15px"},
)

# Log display widget
log_display = pn.widgets.TextAreaInput(
    name="Log Output",
    value="",
    placeholder="Log messages will appear here...",
    disabled=True,
    height=200,
    sizing_mode="stretch_width",
)

# Collapsible card for log display
log_card = pn.Card(
    log_display,
    title="Logs & Messages",
    collapsed=True,
    collapsible=True,
    sizing_mode="stretch_width",
)

# Add the custom handler to the logger
panel_handler = PanelLogHandler(log_display)
panel_handler.setFormatter(logging.Formatter(FORMAT))
logger.addHandler(panel_handler)

# LAYOUT
download_row = pn.Row(rfc_selector, download_configs_button)

column = pn.Column(
    IPyWidget(lmap, sizing_mode="stretch_both", min_height=500),
    download_row,
    pn.Row(download_dir_text),
    pn.Row(indeterminate),
    log_card,
)

logo_path = Path(__file__).parent / "images" / "CIROHLogo_200x200.png"
template = pn.template.FastListTemplate(
    site="HEFS-FEWS",
    title="Exploration System Dashboard",
    logo=str(logo_path),
    header_background=ACCENT_BASE_COLOR,
    accent_base_color=ACCENT_BASE_COLOR,
    main=[column],
).servable()
