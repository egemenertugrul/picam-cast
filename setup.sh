#!/usr/bin/env bash
# Setup script for noir-camera-stream on Raspberry Pi (64-bit OS, Pi 4/5)
#
# Usage:
#   bash setup.sh
#   bash setup.sh --zip-url https://your-server.com/Install_NDI_SDK_v6_Linux.zip

set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'
info()    { echo -e "${GREEN}[setup]${NC} $*"; }
warn()    { echo -e "${YELLOW}[warn]${NC}  $*"; }
die()     { echo -e "${RED}[error]${NC} $*" >&2; exit 1; }

# ── Args ──────────────────────────────────────────────────────────────────────
NDI_ZIP_URL=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --zip-url) NDI_ZIP_URL="$2"; shift 2 ;;
        *) die "Unknown argument: $1. Usage: bash setup.sh [--zip-url <url>]" ;;
    esac
done

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NDI_VERSION="6.3.2.0"
NDI_LIB_VERSION="6.3.2"
NDI_TAR_URL="https://downloads.ndi.tv/SDK/NDI_SDK_Linux/Install_NDI_SDK_v6_Linux.tar.gz"
NDI_SDK_DIR="/tmp/NDI SDK for Linux"
NDI_SRC_DIR="/tmp/ndi-python-src"

# ── 1. Verify platform ────────────────────────────────────────────────────────
info "Checking platform..."
[[ "$(uname -m)" == "aarch64" ]] || die "This script requires a 64-bit (aarch64) Raspberry Pi OS."
python3 -c "import sys; assert sys.version_info >= (3,11)" 2>/dev/null \
    || die "Python 3.11+ required. Found: $(python3 --version)"
info "Platform OK — $(uname -m), $(python3 --version)"

# ── 2. System packages ────────────────────────────────────────────────────────
info "Installing system dependencies..."
sudo apt-get update -qq
sudo apt-get install -y cmake libcap-dev git 2>&1 | grep -E "^(Setting up|already)" || true
info "System dependencies OK."

# ── 3. uv ─────────────────────────────────────────────────────────────────────
if ! command -v uv &>/dev/null && [[ ! -x "$HOME/.local/bin/uv" ]]; then
    info "Installing uv..."
    curl -LsSf https://astral.sh/uv/install.sh | sh
fi
UV="${HOME}/.local/bin/uv"
[[ -x "$UV" ]] || UV="$(command -v uv)"
info "uv OK — $("$UV" --version)"

# ── 4. NDI SDK (system libraries) ─────────────────────────────────────────────
if ldconfig -p | grep -q "libndi.so.${NDI_LIB_VERSION%%.*}"; then
    info "NDI SDK already installed — skipping."
else
    info "Downloading NDI SDK..."
    if wget -q --show-progress "$NDI_TAR_URL" -O /tmp/Install_NDI_SDK_v6_Linux.tar.gz 2>/dev/null; then
        info "Extracting .tar.gz..."
        cd /tmp && tar -xzf Install_NDI_SDK_v6_Linux.tar.gz
    else
        warn ".tar.gz download failed — trying .zip fallback..."
        [[ -n "$NDI_ZIP_URL" ]] || die ".tar.gz download failed and no --zip-url provided. Pass one with: bash setup.sh --zip-url <url>"
        sudo apt-get install -y unzip -qq
        wget -q --show-progress "$NDI_ZIP_URL" -O /tmp/Install_NDI_SDK_v6_Linux.zip \
            || die ".zip download also failed. Check the URL and your connection."
        info "Extracting .zip..."
        cd /tmp && unzip -q Install_NDI_SDK_v6_Linux.zip
    fi
    echo "y" | sh /tmp/Install_NDI_SDK_v6_Linux.sh >/dev/null 2>&1 || true

    LIB_SRC="${NDI_SDK_DIR}/lib/aarch64-rpi4-linux-gnueabi/libndi.so.${NDI_LIB_VERSION}"
    [[ -f "$LIB_SRC" ]] || die "NDI library not found at: $LIB_SRC"

    info "Installing NDI libraries..."
    sudo cp "$LIB_SRC" /usr/lib/
    sudo ln -sf "/usr/lib/libndi.so.${NDI_LIB_VERSION}" "/usr/lib/libndi.so.${NDI_LIB_VERSION%%.*}"
    sudo ln -sf "/usr/lib/libndi.so.${NDI_LIB_VERSION}" /usr/lib/libndi.so
    sudo cp "${NDI_SDK_DIR}/include/Processing.NDI.Lib.h" /usr/include/
    sudo ldconfig
    info "NDI SDK installed."
fi

# ── 5. Build ndi-python ────────────────────────────────────────────────────────
SO_NAME="NDIlib.cpython-$(python3 -c 'import sys; print(f"{sys.version_info.major}{sys.version_info.minor}")')-aarch64-linux-gnu.so"
SO_PATH="${NDI_SRC_DIR}/build_manual/${SO_NAME}"

if [[ -f "$SO_PATH" ]]; then
    info "ndi-python already built — skipping."
else
    info "Cloning ndi-python..."
    rm -rf "$NDI_SRC_DIR"
    git clone --recurse-submodules https://github.com/buresu/ndi-python.git "$NDI_SRC_DIR" -q

    info "Building ndi-python (this takes a minute)..."
    mkdir -p "${NDI_SRC_DIR}/build_manual"
    cmake -S "$NDI_SRC_DIR" -B "${NDI_SRC_DIR}/build_manual" \
        -DCMAKE_BUILD_TYPE=Release \
        -DPYTHON_EXECUTABLE="$(which python3)" \
        -Wno-dev -DCMAKE_WARN_DEPRECATED=OFF \
        >/dev/null 2>&1
    make -C "${NDI_SRC_DIR}/build_manual" -j"$(nproc)" >/dev/null 2>&1
    [[ -f "$SO_PATH" ]] || die "Build failed — .so not found at $SO_PATH"
    info "ndi-python built."
fi

# ── 6. Python venv ─────────────────────────────────────────────────────────────
VENV="${SCRIPT_DIR}/.venv"
if [[ -d "$VENV" ]]; then
    info "Venv already exists — skipping creation."
else
    info "Creating venv..."
    "$UV" venv --system-site-packages "$VENV"
fi

PYTHON="${VENV}/bin/python3"
SITE="$("$PYTHON" -c "import site; print(site.getsitepackages()[0])")"

# ── 7. Install NDIlib into venv ────────────────────────────────────────────────
if "$PYTHON" -c "import NDIlib" &>/dev/null; then
    info "NDIlib already in venv — skipping."
else
    info "Copying NDIlib into venv..."
    mkdir -p "${SITE}/NDIlib"
    cp "${NDI_SRC_DIR}/NDIlib/__init__.py" "${SITE}/NDIlib/"
    cp "$SO_PATH" "${SITE}/NDIlib/"
fi

# ── 8. Python dependencies ─────────────────────────────────────────────────────
info "Installing Python dependencies..."
"$UV" pip install numpy --quiet

# ── 9. Smoke test ─────────────────────────────────────────────────────────────
info "Running smoke test..."
"$PYTHON" - <<'EOF'
import NDIlib as ndi
import numpy
from picamera2 import Picamera2
assert ndi.initialize(), "NDI init failed"
ndi.destroy()
print("NDI:", ndi.version())
print("numpy:", numpy.__version__)
print("picamera2: OK")
EOF

echo ""
echo -e "${GREEN}✓ Setup complete.${NC}"
echo ""
echo "Run the stream:"
echo "  .venv/bin/python3 stream_ndi.py"
echo "  .venv/bin/python3 stream_ndi.py --mode 720p60"
echo "  .venv/bin/python3 stream_ndi.py --help"
