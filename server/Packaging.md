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
4. Install it on the VM: `source ~/venv/bin/activate && pip install --upgrade new_version.whl`
5. Restart the service: `sudo systemctl restart jumpsync`
