"""
Jupyter Server Proxy configuration for Panel Dashboard
"""
import shutil
import sys
from pathlib import Path


def setup_panel_dashboard():
    """
    Setup function for jupyter-server-proxy to launch Panel dashboard.
    
    Returns a dict with configuration for the proxy.
    """
    # Get the path to the dashboard notebook
    import hefs_fews_hub
    pkg_path = Path(hefs_fews_hub.__file__).parent
    # Use the .py file instead of notebook - notebooks need a kernel for ipyleaflet
    dashboard_path = pkg_path / "panel_dashboard.py"
    icon_path = pkg_path / "images" / "configuration.svg"
    
    
    # Find panel executable
    panel_cmd = shutil.which("panel")
    if not panel_cmd:
        panel_cmd = "panel"
    
    config = {
        "command": [
            panel_cmd,
            "serve",
            str(dashboard_path),
            "--port", "{port}",
            "--allow-websocket-origin=*",
            # "--log-level", "debug",
            # "--show", "--autoreload"
        ],
        "timeout": 30,
        "absolute_url": False,
        "launcher_entry": {
            "enabled": True,
            "title": "HEFS FEWS Dashboard",
            "category": "Notebook",
            "icon_path": str(icon_path)
        },
        "environment": {
            "BOKEH_ALLOW_WS_ORIGIN": "*",
            # "BOKEH_LOG_LEVEL" : "debug",
            # "BOKEH_PY_LOG_LEVEL": "debug",
            # "PANEL_LOG_LEVEL": "debug"
        }
    }
    
    print(f"[Panel Proxy] Dashboard path: {dashboard_path}", file=sys.stderr)
    print(f"[Panel Proxy] Panel command: {panel_cmd}", file=sys.stderr)
    print(f"[Panel Proxy] Full command: {config['command']}", file=sys.stderr)
    print(f"[Panel Proxy] Config: {config}", file=sys.stderr)
    
    return config
