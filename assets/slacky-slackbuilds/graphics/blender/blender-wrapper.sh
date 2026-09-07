#!/usr/bin/env bash
# ==============================================================================
#  Blender 5.2.x Linux Runtime Environment Wrapper
#  Configures NVIDIA CUDA / OptiX, AMD ROCm / HIP, and 3Dconnexion SpaceMouse
# ==============================================================================
set -euo pipefail

# 1. Resolve Blender Installation Root
BLENDER_ROOT="/opt/blender-5.2.1"
[ -d "$BLENDER_ROOT" ] || BLENDER_ROOT="/opt/blender"

if [ ! -x "$BLENDER_ROOT/blender" ]; then
    echo "Error: Blender binary not found at $BLENDER_ROOT/blender" >&2
    exit 1
fi

# 2. Configure System Limits
ulimit -n 1048576 2>/dev/null || true

# 3. GPU Hardware Acceleration (CUDA/OptiX for NVIDIA, ROCm/HIP for AMD)
if lspci 2>/dev/null | grep -i "vga\|3d" | grep -qi "nvidia"; then
    # NVIDIA CUDA / OptiX Runtime (RTX 5080 Blackwell support)
    [ -d "/usr/local/cuda" ] && export CUDA_PATH="/usr/local/cuda"
    export LD_LIBRARY_PATH="/usr/lib64:${LD_LIBRARY_PATH:-}"
    export CYCLES_CUDA_EXTRA_CFLAGS="-O3"
    export __GL_SHADER_DISK_CACHE=1
elif lspci 2>/dev/null | grep -i "vga\|3d" | grep -qi "amd\|radeon"; then
    # AMD ROCm / HIP Runtime
    [ -d "/opt/rocm" ] && export ROCM_PATH="/opt/rocm"
    [ -d "/opt/rocm/hip" ] && export HIP_PATH="/opt/rocm/hip"
    export HSA_OVERRIDE_GFX_VERSION="${HSA_OVERRIDE_GFX_VERSION:-}"
fi

# 4. 3Dconnexion SpaceMouse Verification
# Blender natively links to libspnav; verify daemon socket exists
if [ -c "/dev/hidraw0" ] && lsusb 2>/dev/null | grep -qi "256f:\|046d:c6"; then
    if [ ! -S "/run/spnav.sock" ] && [ ! -S "/var/run/spnav.sock" ]; then
        if [ -x /etc/rc.d/rc.spacenavd ] && ! pgrep -x spacenavd >/dev/null 2>&1; then
            echo "[Blender] 3Dconnexion SpaceMouse detected; launching spacenavd..."
            sudo /etc/rc.d/rc.spacenavd start 2>/dev/null || true
        fi
    fi
fi

# 5. Launch Blender
exec "$BLENDER_ROOT/blender" "$@"
