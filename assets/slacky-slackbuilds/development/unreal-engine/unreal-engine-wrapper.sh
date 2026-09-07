#!/usr/bin/env bash
# ==============================================================================
#  Unreal Engine 5 (Universal) Linux Runtime Environment Wrapper
#  Configures CUDA, ROCm/OpenCL, Vulkan SM6, and 3Dconnexion SpaceMouse HID
# ==============================================================================
set -euo pipefail

# 1. Resolve Unreal Engine Installation Path
UE_ROOT=""

# Check explicit config file first
if [ -f "/etc/unreal-engine.conf" ]; then
    CONF_ROOT=$(cat "/etc/unreal-engine.conf" 2>/dev/null || true)
    [ -d "$CONF_ROOT/Engine/Binaries/Linux" ] && UE_ROOT="$CONF_ROOT"
fi

# Fallback: Check installed /opt trees or user storage mounts
if [ -z "$UE_ROOT" ]; then
    for cand in /opt/unreal-engine-* /opt/unreal-engine /home/tux/Games1/UnrealEngine-*; do
        if [ -d "$cand/Engine/Binaries/Linux" ]; then
            UE_ROOT="$cand"
            break
        fi
    done
fi

if [ -z "$UE_ROOT" ]; then
    echo "Error: Could not locate an Unreal Engine installation." >&2
    echo "Please run install-unreal-engine.sh or configure /etc/unreal-engine.conf" >&2
    exit 1
fi

UE_BIN="$UE_ROOT/Engine/Binaries/Linux/UnrealEditor"

if [ ! -x "$UE_BIN" ]; then
    echo "Error: UnrealEditor executable not found or not executable at: $UE_BIN" >&2
    exit 1
fi

# 2. Configure Resource Limits
ulimit -n 1048576 2>/dev/null || true

# 3. Detect and Configure GPU Acceleration (NVIDIA CUDA / AMD ROCm)
if lspci 2>/dev/null | grep -i "vga\|3d" | grep -qi "nvidia"; then
    # NVIDIA CUDA and Vulkan SM6 runtime
    [ -f "/etc/vulkan/icd.d/nvidia_icd.json" ] && export VK_ICD_FILENAMES="/etc/vulkan/icd.d/nvidia_icd.json"
    [ -d "/usr/local/cuda" ] && export CUDA_PATH="/usr/local/cuda"
    export LD_LIBRARY_PATH="/usr/lib64:${LD_LIBRARY_PATH:-}"
    export __GL_SHADER_DISK_CACHE=1
    export __GL_SHADER_DISK_CACHE_SKIP_CLEANUP=1
elif lspci 2>/dev/null | grep -i "vga\|3d" | grep -qi "amd\|radeon"; then
    # AMD ROCm OpenCL and RADV Vulkan runtime
    export AMD_VULKAN_ICD="RADV"
    export RADV_PERFTEST="nggc,sam"
fi

# 4. 3Dconnexion SpaceMouse Integration Check
# Verify that the universal udev rules are active and spacenavd is available
if [ -c "/dev/hidraw0" ]; then
    # Check if a 3Dconnexion device is connected
    if lsusb 2>/dev/null | grep -qi "256f:\|046d:c6"; then
        if [ -x /etc/rc.d/rc.spacenavd ] && ! pgrep -x spacenavd >/dev/null 2>&1; then
            echo "[UnrealEngine] 3Dconnexion device detected; starting spacenavd daemon..."
            sudo /etc/rc.d/rc.spacenavd start 2>/dev/null || true
        fi
    fi
fi

# 5. Launch Unreal Editor
exec "$UE_BIN" "$@"
