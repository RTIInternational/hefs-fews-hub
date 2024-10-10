#!/bin/bash
voila /opt/hefs_fews_dashboard/dashboard.ipynb --port=8866 --no-browser &
firefox http://localhost:8866/
