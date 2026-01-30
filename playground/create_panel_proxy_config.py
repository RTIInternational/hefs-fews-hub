from anyio import Path
from hefs_fews_hub import panel_dashboard

fp = Path("/home/jovyan/jupyter-panel-proxy.yml")

with open(fp, "w") as f:
    f.writelines(
        [
            "apps:\n",
            f"  - {panel_dashboard.__file__}\n",
            "oauth_optional: true\n"
        ]
    )