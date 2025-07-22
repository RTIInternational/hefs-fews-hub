# Server settings
# from jupyter_server.serverapp import get_config
ORIGIN='*'

c = get_config()  # noqa
# c.ServerApp.ip = 'localhost'
# c.ServerApp.port = 8080
# c.ServerApp.open_browser = False

c.ServerProxy.servers = {
    # "hefs-fews": {
    #     "command": ["python3", "-m", "http.server", "{port}"],
    #     "absolute_url": False
    # },
    "panel-dashboard": {
        "command": [
            "panel", "serve", "panel_dash.ipynb",
            "--port={port}",
            "--allow-websocket-origin=localhost:8080",
            # "--allow-websocket-origin=*",
            "--show",
            "--prefix=/panel-dashboard",
        ],
        "absolute_url": True,
        "url": "http://localhost:8080/panel-dashboard",
        "port": 8080,
        # "launcher_entry": {
        #     "enabled": True,
        #     "icon_path": "https://panel.holoviz.org/_static/logo.png",
        #     "title": "Panel Dashboard"
        # },
        "timeout": 30
    }
}
