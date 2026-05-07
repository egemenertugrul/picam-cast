# picam-cast

Stream any Raspberry Pi camera as an NDI source. Auto-discoverable on the local network — zero configuration on the receiver side.

## Usage

```bash
# List modes available for your specific sensor
.venv/bin/python3 stream_ndi.py --list-modes

# Stream (default: 1080p30, source name "Pi Camera")
.venv/bin/python3 stream_ndi.py

# Custom mode and source name
.venv/bin/python3 stream_ndi.py --mode 720p60 --name "Stage Camera"

# Show live fps stats
.venv/bin/python3 stream_ndi.py -v

# Stop: Ctrl+C
```

## Modes

Modes are derived from the connected sensor at startup. Run `--list-modes` to see what your camera supports.

| Mode | Resolution | FPS |
|---|---|---|
| `max` | Sensor native | 30 |
| `4k30` | 3840×2160 | 30 |
| `1080p60` | 1920×1080 | 60 |
| `1080p30` | 1920×1080 | 30 |
| `720p60` | 1280×720 | 60 |
| `720p30` | 1280×720 | 30 |
| `480p30` | 854×480 | 30 |

Modes that exceed the sensor's native resolution are automatically excluded.

## Receiving

**TouchDesigner:** Add an **NDI In TOP** — the Pi appears in the source dropdown by name automatically.

**Other tools:** [NDI Tools](https://ndi.video/tools/) (free), OBS, Resolume, VLC all support NDI natively or via plugin.

## Network

Designed for wired Ethernet on a shared LAN. Both Pi and receiver must be on the same network segment — NDI uses mDNS for auto-discovery.

## Setup

```bash
# Standard
bash setup.sh

# If the default NDI SDK download fails, provide your own .zip URL
bash setup.sh --zip-url https://your-server.com/Install_NDI_SDK_v6_Linux.zip
```

Requires a 64-bit Raspberry Pi OS (Pi 4 or Pi 5). `picamera2` must be installed via apt (`sudo apt install python3-picamera2`).

## Tested cameras

| Camera | Sensor | Max resolution |
|---|---|---|
| Camera Module 2 NoIR | IMX219 | 3280×2464 |

*Contributions welcome for other modules (HQ, Camera Module 3, etc.)*
