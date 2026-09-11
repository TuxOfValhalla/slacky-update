#!/bin/bash
# ==============================================================================
#  Volt GUI Slackware Launch Wrapper
# ==============================================================================

export VOLT_GUI_DIR="/opt/volt-gui"

# Stage isolated PySide6/Shiboken6 if bundled in /opt/volt-gui/lib
PY_VER=$(python3 -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || echo "3.11")
export PYTHONPATH="${VOLT_GUI_DIR}:${VOLT_GUI_DIR}/lib/python${PY_VER}/site-packages:${VOLT_GUI_DIR}/lib:${PYTHONPATH:-}"

if [ -f "${VOLT_GUI_DIR}/volt-gui.py" ]; then
    exec python3 "${VOLT_GUI_DIR}/volt-gui.py" "$@"
elif [ -f "${VOLT_GUI_DIR}/src/volt-gui/volt-gui.py" ]; then
    exec python3 "${VOLT_GUI_DIR}/src/volt-gui/volt-gui.py" "$@"
elif [ -f "/usr/share/volt-gui/volt-gui.py" ]; then
    exec python3 "/usr/share/volt-gui/volt-gui.py" "$@"
elif command -v volt-gui.py >/dev/null 2>&1; then
    exec python3 "$(command -v volt-gui.py)" "$@"
else
    echo "Error: volt-gui script not found in ${VOLT_GUI_DIR}." >&2
    exit 1
fi
