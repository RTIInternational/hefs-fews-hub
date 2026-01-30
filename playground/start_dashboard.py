import argparse
import subprocess
import sys
import time
from hefs_fews_hub import panel_dashboard
import socket

def main():
    parser = argparse.ArgumentParser(description="Start Panel dashboard and open in browser.")
    parser.add_argument(
        "--port", type=int, default=5006, help="Port to serve the dashboard on (default: 5006)"
    )
    parser.add_argument(
        "--browser", type=str, default="firefox", help="Browser to open (default: firefox)"
    )
    args = parser.parse_args()

    module_path = panel_dashboard.__file__
    print(f"Module path: {module_path}")
    # Start the Panel server
    panel_cmd = [
        sys.executable, "-m", "panel", "serve",
        f"--port={args.port}", 
        # "--dev", 
        str(module_path)
    ]
    # Check if a similar Panel server process is already running on the given port

    def is_port_in_use(port):
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            return s.connect_ex(('localhost', port)) == 0

    if is_port_in_use(args.port):
        print(f"Panel server already running on port {args.port}.")
        url = f"http://localhost:{args.port}/panel_dashboard"
        print(f"Opening browser at: {url}")
        subprocess.Popen([args.browser, url])
        sys.exit(0)
    panel_proc = subprocess.Popen(panel_cmd)
    time.sleep(10)

    # Check if the process is still running
    if panel_proc.poll() is not None:
        print("Panel process failed to start.", file=sys.stderr)
        sys.exit(1)

    # Open the dashboard in the browser
    url = f"http://localhost:{args.port}/panel_dashboard"
    print(f"Browser URL: {url}")
    subprocess.Popen([args.browser, url])

    # Wait for the panel process to finish
    panel_proc.wait()

if __name__ == "__main__":
    main()
