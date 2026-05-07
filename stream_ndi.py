#!/usr/bin/env python3
"""picam-cast — stream any Raspberry Pi camera as an NDI source."""

import argparse
import logging
import os
import signal
import sys
import time

# Suppress libcamera and picamera2 logging before importing them
os.environ["LIBCAMERA_LOG_LEVELS"] = "*:ERROR"
os.environ["LIBCAMERA_LOG_FILE"] = "/dev/null"
logging.getLogger("picamera2").setLevel(logging.ERROR)

import NDIlib as ndi
import numpy as np
from picamera2 import Picamera2

# Standard presets: applied if the sensor can meet or exceed the resolution.
# fps is a target — picamera2 will get as close as the sensor allows.
PRESETS = {
    "max":    {"size": None,         "fps": 30},  # sensor native resolution
    "4k30":   {"size": (3840, 2160), "fps": 30},
    "1080p60":{"size": (1920, 1080), "fps": 60},
    "1080p30":{"size": (1920, 1080), "fps": 30},
    "720p60": {"size": (1280, 720),  "fps": 60},
    "720p30": {"size": (1280, 720),  "fps": 30},
    "480p30": {"size": (854, 480),   "fps": 30},
}


def get_sensor_modes(cam: Picamera2) -> dict:
    """Return available preset modes for the connected sensor."""
    sw, sh = cam.sensor_resolution
    available = {}
    for name, cfg in PRESETS.items():
        if cfg["size"] is None:
            available[name] = {"size": (sw, sh), "fps": cfg["fps"]}
        elif cfg["size"][0] <= sw and cfg["size"][1] <= sh:
            available[name] = cfg
    return available


def run(source_name: str, mode: str, verbose: bool):
    if not ndi.initialize():
        print("ERROR: NDI initialisation failed — is libndi.so accessible?", file=sys.stderr)
        sys.exit(1)

    send_settings = ndi.SendCreate()
    send_settings.ndi_name = source_name
    sender = ndi.send_create(send_settings)
    if not sender:
        print("ERROR: Could not create NDI sender.", file=sys.stderr)
        ndi.destroy()
        sys.exit(1)

    cam = Picamera2()
    available = get_sensor_modes(cam)

    if mode not in available:
        sensor_res = "×".join(map(str, cam.sensor_resolution))
        print(
            f"ERROR: mode '{mode}' is not supported by this sensor ({sensor_res}).\n"
            f"Available modes: {', '.join(available)}",
            file=sys.stderr,
        )
        cam.close()
        ndi.send_destroy(sender)
        ndi.destroy()
        sys.exit(1)

    cfg = available[mode]
    width, height, fps = cfg["size"][0], cfg["size"][1], cfg["fps"]

    video_config = cam.create_video_configuration(
        main={"size": (width, height), "format": "RGB888"},
        controls={"FrameRate": fps},
    )
    cam.configure(video_config)
    cam.start()
    time.sleep(1)  # let AEC/AWB settle

    video_frame = ndi.VideoFrameV2()
    video_frame.xres = width
    video_frame.yres = height
    video_frame.FourCC = ndi.FOURCC_VIDEO_TYPE_RGBX
    video_frame.frame_rate_N = fps
    video_frame.frame_rate_D = 1
    video_frame.picture_aspect_ratio = width / height
    video_frame.frame_format_type = ndi.FRAME_FORMAT_TYPE_PROGRESSIVE
    video_frame.timecode = ndi.SEND_TIMECODE_SYNTHESIZE
    video_frame.line_stride_in_bytes = width * 4

    running = True

    def _stop(sig, frame):
        nonlocal running
        running = False
        raise KeyboardInterrupt

    signal.signal(signal.SIGINT, _stop)
    signal.signal(signal.SIGTERM, _stop)

    sensor_model = cam.camera_properties.get("Model", "unknown")
    print(f"Sensor : {sensor_model} ({cam.sensor_resolution[0]}×{cam.sensor_resolution[1]})")
    print(f"Stream : {width}×{height} @ {fps}fps  [{mode}]")
    print(f"NDI    : {source_name}")
    print("Ctrl+C to stop.")

    # Allocate once — the binding stores a raw C pointer to this buffer.
    # Writing in-place each frame avoids reallocation and dangling pointer crashes.
    frame_buffer = np.zeros((height, width, 4), dtype=np.uint8)
    frame_buffer[:, :, 3] = 255  # alpha always 255
    video_frame.data = frame_buffer

    frame_count = 0
    t_start = time.monotonic()

    try:
        while running:
            frame_rgb = cam.capture_array("main")
            frame_buffer[:, :, :3] = frame_rgb
            ndi.send_send_video_v2(sender, video_frame)

            frame_count += 1
            if verbose and frame_count % fps == 0:
                elapsed = time.monotonic() - t_start
                print(f"  {frame_count} frames  {frame_count / elapsed:.1f} fps")
    except KeyboardInterrupt:
        pass
    finally:
        print("\nStopping…")
        cam.stop()
        cam.close()
        ndi.send_destroy(sender)
        ndi.destroy()
        print("Done.")


def list_modes():
    cam = Picamera2()
    available = get_sensor_modes(cam)
    model = cam.camera_properties.get("Model", "unknown")
    res = cam.sensor_resolution
    cam.close()
    print(f"Sensor: {model}  ({res[0]}×{res[1]})")
    print("\nAvailable modes:")
    for name, cfg in available.items():
        w, h = cfg["size"]
        print(f"  {name:<10}  {w}×{h} @ {cfg['fps']}fps")


def main():
    parser = argparse.ArgumentParser(
        description="picam-cast — stream any Pi camera as an NDI source"
    )
    parser.add_argument(
        "--name", default="Pi Camera",
        help="NDI source name visible to receivers (default: 'Pi Camera')"
    )
    parser.add_argument(
        "--mode", default="1080p30",
        help="Stream mode (default: 1080p30). See --list-modes for options."
    )
    parser.add_argument(
        "--list-modes", action="store_true",
        help="List modes available for the connected sensor and exit"
    )
    parser.add_argument(
        "-v", "--verbose", action="store_true",
        help="Print live fps stats"
    )
    args = parser.parse_args()

    if args.list_modes:
        list_modes()
        return

    run(args.name, args.mode, args.verbose)


if __name__ == "__main__":
    main()
