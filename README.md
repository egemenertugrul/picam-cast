# picam-cast

Streams a Raspberry Pi camera over NDI. Shows up on the network automatically, no IP config or port forwarding needed.

Built for live performance use over wired Ethernet. The receiver just needs TouchDesigner (or any NDI tool) on the same network.

## Setup

```bash
bash setup.sh

# if the NDI SDK download fails, pass your own mirror
bash setup.sh --zip-url https://your-server.com/Install_NDI_SDK_v6_Linux.zip
```

Requires 64-bit Raspberry Pi OS and `picamera2` (`sudo apt install python3-picamera2`).

## Running

```bash
# see what modes your camera supports
.venv/bin/python3 stream_ndi.py --list-modes

# start streaming
.venv/bin/python3 stream_ndi.py

# custom mode and source name
.venv/bin/python3 stream_ndi.py --mode 720p60 --name "Stage Cam"

# Ctrl+C to stop
```

## Modes

| Mode | Resolution | FPS |
|---|---|---|
| `max` | sensor native | 30 |
| `4k30` | 3840×2160 | 30 |
| `1080p60` | 1920×1080 | 60 |
| `1080p30` | 1920×1080 | 30 |
| `720p60` | 1280×720 | 60 |
| `720p30` | 1280×720 | 30 |
| `480p30` | 854×480 | 30 |

Modes that exceed the sensor's resolution won't show up in `--list-modes`.

## Receiving

In TouchDesigner, add an **NDI In TOP** and the Pi will appear in the source list by name.

For other tools (OBS, Resolume, VLC) install [NDI Tools](https://ndi.video/tools/).

## Tested on

| Pi | Camera | Sensor |
|---|---|---|
| Raspberry Pi 4 (2GB) | Camera Module 2 NoIR | IMX219 |
