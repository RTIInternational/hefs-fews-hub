#!/bin/bash
voila /home/jovyan/hefs_fews/dashboard.ipynb --port=8866 --no-browser &
firefox http://localhost:8866/
