<p align="center">
  <img src=".github/images/banner.svg" alt="RPi-WiFi-Fallback Banner" width="800">
</p>

<h1 align="center">RPi-WiFi-Fallback</h1>

<p align="center">
  <strong>WiFi Fallback for Raspberry Pi</strong><br>
  Auto AP hotspot + captive portal when disconnected. No monitor needed.
</p>

<p align="center">
  <a href="#quick-start">Quick Start</a> •
  <a href="#features">Features</a> •
  <a href="#configuration">Configuration</a> •
  <a href="#faq">FAQ</a>
</p>

<p align="center">
  <img src="https://img.shields.io/badge/Platform-Raspberry%20Pi-c51a4a?style=flat-square&logo=raspberrypi" alt="Platform">
  <img src="https://img.shields.io/badge/OS-Bookworm%20|%20Trixie-blue?style=flat-square" alt="OS">
  <img src="https://img.shields.io/badge/License-MIT-green?style=flat-square" alt="License">
  <img src="https://img.shields.io/badge/Python-3.11+-yellow?style=flat-square&logo=python&logoColor=white" alt="Python">
</p>

<p align="center">
  <a href="README.md">简体中文</a> | <strong>English</strong>
</p>

---

## Features

- **Auto Detection**: Checks WiFi connection every 15 seconds
- **AP Hotspot Fallback**: Automatically starts WPA2-encrypted AP when disconnected
- **Captive Portal**: Auto-popup configuration page (iOS/Android/Windows)
- **Web Configuration**: Mobile-friendly WiFi setup interface
- **Auto Recovery**: Automatically closes hotspot and connects to new WiFi after configuration

## Compatibility

### Supported OS

| OS | Version | Status |
|------|------|------|
| Raspberry Pi OS | 64-bit (Debian Bookworm) | ✅ Tested |
| Raspberry Pi OS | 64-bit (Debian Trixie) | ✅ Tested |

### Supported Hardware

| Hardware | Architecture | Status |
|------|------|------|
| Raspberry Pi Zero W / WH | aarch64 (64-bit ARM) | ✅ Tested |
| Raspberry Pi Zero 2 W / WH | aarch64 (64-bit ARM) | ✅ Tested |
| Raspberry Pi 3B / 3B+ | aarch64 (64-bit ARM) | ✅ Compatible |
| Raspberry Pi 4B | aarch64 (64-bit ARM) | ✅ Compatible |
| Raspberry Pi 5 | aarch64 (64-bit ARM) | ✅ Compatible |

> **Note**: Requires Raspberry Pi with WiFi capability and 64-bit OS.

### Dependencies

| Dependency | Description |
|------|------|
| NetworkManager | Network management service (usually pre-installed) |
| nftables | Firewall framework (default in Bookworm/Trixie) |
| Python 3.11+ | Runs the web configuration interface |

## Quick Start

### One-Line Install

```bash
# Download and run the install script
curl -sSL https://raw.githubusercontent.com/CairoLee/RPi-WiFi-Fallback/main/dist/setup.sh | sudo bash -s install
```

### Manual Install

```bash
# Clone the repository
git clone https://github.com/CairoLee/RPi-WiFi-Fallback.git
cd RPi-WiFi-Fallback

# Run the install script
sudo ./setup.sh install
```

> **📶 Default Hotspot Info**
>
> When WiFi connection fails, the Raspberry Pi will automatically create the following AP hotspot:
>
> | Item | Default Value |
> |------|--------|
> | Hotspot Name | `RPi-WiFi-Setup` |
> | Hotspot Password | `raspberry2026` |
>
> To customize the hotspot name or password, see the [Configuration](#configuration) section below.

### Uninstall

```bash
sudo ./setup.sh uninstall
```

## How It Works

<p align="center">
  <img src=".github/images/wifi-fallback-workflow.png" alt="WiFi Fallback Workflow">
</p>

<details>
<summary>📝 Workflow Description</summary>

1. **systemd Timer** - Triggers check every 15 seconds
2. **Network Detection** - Checks connectivity via default gateway
3. **Connected** - No action needed when network is normal
4. **Disconnected** - Starts AP hotspot mode
5. **Web Service** - Launches captive portal to guide user configuration
6. **User Configuration** - Select and connect to new WiFi via web interface
7. **Restore Connection** - Closes hotspot, connects to newly configured WiFi

</details>

## Configuration

### Method 1: Environment Variables (Recommended for One-Line Install)

Customize configuration via environment variables without modifying files:

```bash
# Customize during one-line install
curl -sSL https://raw.githubusercontent.com/CairoLee/RPi-WiFi-Fallback/main/dist/setup.sh | \
  WIFI_AP_SSID="Raspberry-Pi-WiFi" \
  WIFI_AP_PASSWORD="secret123" \
  sudo -E bash -s install
```

Supported environment variables:

| Variable | Description | Default |
|----------|------|--------|
| `WIFI_AP_SSID` | AP hotspot name | `RPi-WiFi-Setup` |
| `WIFI_AP_PASSWORD` | AP hotspot password (min 8 chars) | `raspberry2026` |
| `WIFI_AP_CONNECTION_NAME` | NetworkManager connection name | `RPi-WiFi-Setup-Hotspot` |
| `WIFI_AP_IP` | AP IP address range | `192.168.4.1/24` |

### Method 2: Edit Configuration File

After cloning the repository, edit `config.sh` before installation:

```bash
WIFI_AP_SSID="RPi-WiFi-Setup"                      # AP hotspot SSID
WIFI_AP_PASSWORD="raspberry2026"                   # AP hotspot password (min 8 chars)
WIFI_AP_CONNECTION_NAME="RPi-WiFi-Setup-Hotspot"   # NetworkManager connection name
WIFI_AP_IP="192.168.4.1/24"                        # AP IP address range
```

## Development Guide

### Project Structure

```
rpi-wifi-fallback/
├── config.sh           # User configuration file
├── build.sh            # Build script
├── src/                # Source files directory
│   ├── lib/            # Shell script library
│   ├── templates/      # Deployment templates
│   └── main.sh         # Script entry point
├── dist/
│   └── setup.sh        # Build output (single file for deployment)
├── scripts/            # Operations scripts
└── docs/               # Documentation
```

### Development Workflow

```bash
# 1. Modify source files
vim src/templates/app.py

# 2. Build
./build.sh

# 3. Deploy to Raspberry Pi
./scripts/deploy.sh
```

### Installed Components

| File | Location | Description |
|------|------|------|
| `wifi-fallback.sh` | `/usr/local/bin/` | WiFi detection script |
| `wifi-fallback.timer` | `/etc/systemd/system/` | Timer trigger (every 15 seconds) |
| `wifi-fallback.service` | `/etc/systemd/system/` | Fallback service unit |
| `wifi-config.service` | `/etc/systemd/system/` | Web configuration service |
| `app.py` | `/opt/wifi-config/` | Flask web application |

## FAQ

### Captive Portal Not Showing

Some browsers or systems may require manually visiting `http://192.168.4.1`.

> **💡 iPhone Tip**
>
> If the captive portal doesn't automatically appear after connecting to the hotspot on iPhone, try tapping the ⓘ info button next to the connected hotspot name (e.g., `RPi-WiFi-Setup`) in WiFi settings, then go back. This usually triggers the portal page to appear.

### View Logs

```bash
# View system logs
journalctl -t wifi-fallback -f

# View debug logs
cat /tmp/wifi-fallback.log
```

## License

This project is licensed under the [MIT License](LICENSE).

## Contributing

Issues and Pull Requests are welcome!

- [Report Issues](https://github.com/CairoLee/RPi-WiFi-Fallback/issues)
- [Contribute Code](https://github.com/CairoLee/RPi-WiFi-Fallback/pulls)
