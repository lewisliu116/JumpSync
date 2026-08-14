# Packaging and Deploying JumpSync Server

This document outlines the recommended approach to package and deploy the JumpSync server to a Google Cloud Platform (GCP) Linux VM.

We use **Python Wheels (`.whl`)** for clean distribution (similar to `npm`) and **`systemd`** to ensure the server automatically runs on startup and restarts on crashes (similar to `pm2`).

## 1. Package the App (On Your Mac)

Package the application into a Python Wheel:

```bash
# Ensure build tools are installed
python3 -m pip install build

# Build the Wheel package
python3 -m build
```
This will generate a `.whl` file in the `dist/` directory (e.g., `dist/jumpsync_server-1.0.0-py3-none-any.whl`).

## 2. Deploy to the Server

Copy the `.whl` file to your GCP VM using `gcloud` (or standard `scp`):

```bash
gcloud compute scp dist/jumpsync_server-1.0.0-py3-none-any.whl your_username@your-vm-name:~/
```

## 3. Install on the Server

SSH into your VM:

```bash
gcloud compute ssh your_username@your-vm-name
```

Create a virtual environment and install the packaged Wheel:

```bash
# Create a fresh virtual environment in your home directory
python3 -m venv ~/venv
source ~/venv/bin/activate

# Install the Wheel (this installs your app and all dependencies)
pip install jumpsync_server-1.0.0-py3-none-any.whl
```

## 4. Set Environment Variables & Make It Uncrashable with systemd

Configure `systemd` to keep the app running forever in the background and correctly read your environment variables (like API secrets).

First, create a `.env` file in your home directory to securely store your secrets:

```bash
nano ~/.env
```

Add your specific configuration variables inside:
```ini
SYNC_DIR=/path/to/sync/directory
API_SECRET=your_super_secret_key
# Add any other variables you need here
```
*(Save and exit nano: `Ctrl+O`, `Enter`, `Ctrl+X`)*

Next, create the systemd service file:

```bash
sudo nano /etc/systemd/system/jumpsync.service
```

Paste the following configuration (make sure to replace `your_username` with your actual Linux VM username):

```ini
[Unit]
Description=JumpSync Server
After=network.target

[Service]
User=your_username
Group=www-data
Environment="PATH=/home/your_username/venv/bin"

# This line continuously loads your secure environment variables into the app
EnvironmentFile=/home/your_username/.env

# Point uvicorn to your main app module
ExecStart=/home/your_username/venv/bin/uvicorn main:app --host 0.0.0.0 --port 8000

# Automatically restart if the app crashes
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```
*(Save and exit nano: `Ctrl+O`, `Enter`, `Ctrl+X`)*

## 5. Enable and Start the Service

Finally, tell `systemd` to start the app and ensure it launches automatically when the VM reboots:

```bash
# Reload the systemd daemon to read the new service file
sudo systemctl daemon-reload

# Enable the service to start on boot
sudo systemctl enable jumpsync

# Start the service right now
sudo systemctl start jumpsync

# Verify it's running cleanly
sudo systemctl status jumpsync
```

## Updating the Server

When you have new code changes and want to update the live server:
1. Stop the server: `sudo systemctl stop jumpsync` (optional, but good practice).
2. Re-build the wheel on your Mac: `python3 -m build`
3. Copy it over: `gcloud compute scp dist/new_version.whl your_username@your-vm-name:~/`
4. Install it on the VM: `~/venv/bin/pip install --force-reinstall --no-deps new_version.whl`
   *(`--no-deps` skips reinstalling FastAPI/uvicorn/etc; drop it if `requirements` changed. The app `data/` folder is not packaged, so this never touches synced files.)*
5. Restart the service: `sudo systemctl restart jumpsync`
6. Verify: `curl -H "Authorization: Bearer $KEY" http://127.0.0.1:<port>/api/health` should return `{"status":"ok"}`.

### Troubleshooting: broken venv (`required file not found`)

The `~/venv` is bound to the **exact Python interpreter** it was created with. If that interpreter is later removed or upgraded incompatibly (e.g. a Homebrew `python@X` that got uninstalled), every `pip`/`python`/`uvicorn` call in the venv fails with `required file not found`, and **restarting the service will bring it down** — a still-running process survives only because it holds the deleted binary in memory.

Rebuild the venv on a stable system Python **at the same path** (keeps the systemd `ExecStart` valid — no unit edit needed). Note venvs are **not relocatable** — the `bin/` launchers hard-code their absolute path, so always `python3 -m venv` directly at `~/venv`; never build elsewhere and `mv` it in.

```bash
mv ~/venv ~/venv.broken            # running process is unaffected
python3 -m venv ~/venv             # use the system python3 (stable, not Homebrew)
~/venv/bin/pip install fastapi uvicorn pydantic python-dotenv
~/venv/bin/pip install --force-reinstall --no-deps ~/jumpsync_server-1.0.0-py3-none-any.whl
~/venv/bin/python -c "import main"  # validate imports BEFORE restarting
sudo systemctl restart jumpsync
```

> **Note:** other services may share the VM (e.g. a Node app, or another agent with its own venv). Rebuilding `~/venv` and restarting `jumpsync` only affects JumpSync — confirm the others don't reference `~/venv` first, then leave them alone.
