#!/bin/sh
# Bambu Studio Slackware Launch Wrapper

export BAMBU_STUDIO_DIR="/opt/bambu-studio"
export LD_LIBRARY_PATH="${BAMBU_STUDIO_DIR}/lib:${BAMBU_STUDIO_DIR}/bin:${LD_LIBRARY_PATH:-}"
export WEBKIT_EXEC_PATH="${BAMBU_STUDIO_DIR}/lib/webkit2gtk-4.1"
export WEBKIT_INJECTED_BUNDLE_PATH="${BAMBU_STUDIO_DIR}/lib/webkit2gtk-4.1/injected-bundle"

# WebKitGTK sandbox controls
if [ -z "${WEBKIT_FORCE_SANDBOX:-}" ]; then
  export WEBKIT_FORCE_SANDBOX=0
fi

# Prefer system GIO / D-Bus and correct Wayland / X11 rendering flags
if [ -z "${GSETTINGS_SCHEMA_DIR:-}" ]; then
  export GSETTINGS_SCHEMA_DIR="/usr/share/glib-2.0/schemas"
fi

if [ -x "${BAMBU_STUDIO_DIR}/bin/bambu-studio" ]; then
  exec "${BAMBU_STUDIO_DIR}/bin/bambu-studio" "$@"
elif [ -x "${BAMBU_STUDIO_DIR}/AppRun" ]; then
  exec "${BAMBU_STUDIO_DIR}/AppRun" "$@"
else
  echo "Error: Bambu Studio executable not found in ${BAMBU_STUDIO_DIR}" >&2
  exit 1
fi
