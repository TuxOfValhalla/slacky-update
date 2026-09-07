#!/usr/bin/env bash
# ==============================================================================
#  FreeCAD 1.1.x Linux Runtime Environment Wrapper
#  Configures CUDA/OptiX, AMD ROCm, OpenCL, and 3Dconnexion SpaceMouse
# ==============================================================================
set -euo pipefail

# 1. Resolve FreeCAD Installation Root
FC_ROOT="/opt/freecad-1.1.3"
[ -d "$FC_ROOT" ] || FC_ROOT="/opt/freecad"

if [ ! -x "$FC_ROOT/AppRun" ]; then
    echo "Error: FreeCAD AppRun launcher not found at $FC_ROOT/AppRun" >&2
    exit 1
fi

# 2. System Resource Limits
ulimit -n 1048576 2>/dev/null || true

# 3. GPU Hardware Acceleration (CUDA/OptiX for NVIDIA, ROCm for AMD)
if lspci 2>/dev/null | grep -i "vga\|3d" | grep -qi "nvidia"; then
    # NVIDIA CUDA / OptiX for Render Workbench & Solvers
    [ -d "/usr/local/cuda" ] && export CUDA_PATH="/usr/local/cuda"
    export LD_LIBRARY_PATH="/usr/lib64:${LD_LIBRARY_PATH:-}"
    export __GL_SHADER_DISK_CACHE=1
elif lspci 2>/dev/null | grep -i "vga\|3d" | grep -qi "amd\|radeon"; then
    # AMD ROCm / OpenCL Runtime
    [ -d "/opt/rocm" ] && export ROCM_PATH="/opt/rocm"
fi

# 4. 3Dconnexion SpaceMouse Verification
# FreeCAD natively queries /run/spnav.sock via libspnav
if [ -c "/dev/hidraw0" ] && lsusb 2>/dev/null | grep -qi "256f:\|046d:c6"; then
    if [ ! -S "/run/spnav.sock" ] && [ ! -S "/var/run/spnav.sock" ]; then
        if [ -x /etc/rc.d/rc.spacenavd ] && ! pgrep -x spacenavd >/dev/null 2>&1; then
            echo "[FreeCAD] 3Dconnexion SpaceMouse detected; launching spacenavd daemon..."
            sudo /etc/rc.d/rc.spacenavd start 2>/dev/null || true
        fi
    fi
fi

# 5. Launch FreeCAD
exec "$FC_ROOT/AppRun" "$@"
