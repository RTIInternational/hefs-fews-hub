#!/bin/bash
voila /home/jovyan/dashboard.ipynb --port=8866 --no-browser &
firefox http://localhost:8866/
