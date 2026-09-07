if [ -x /usr/bin/update-desktop-database ]; then
  /usr/bin/update-desktop-database -q usr/share/applications >/dev/null 2>&1
fi

if [ -x /usr/bin/update-mime-database ]; then
  /usr/bin/update-mime-database usr/share/mime >/dev/null 2>&1
fi

if [ -d usr/share/icons/hicolor ]; then
  if [ -x /usr/bin/gtk-update-icon-cache ]; then
    /usr/bin/gtk-update-icon-cache -q -f usr/share/icons/hicolor >/dev/null 2>&1 || true
  fi
fi

if [ -x /sbin/udevadm ]; then
  /sbin/udevadm control --reload-rules >/dev/null 2>&1 || true
  /sbin/udevadm trigger --subsystem-match=usb >/dev/null 2>&1 || true
fi

# Ensure DaVinci application support, license, and config directories are writable by normal user
mkdir -p opt/resolve/.license \
         opt/resolve/configs \
         opt/resolve/DolbyVision \
         "opt/resolve/Apple Immersive/Calibration" \
         var/BlackmagicDesign/"DaVinci Resolve" 2>/dev/null || true

chmod 777 opt/resolve \
          opt/resolve/.license \
          opt/resolve/configs \
          opt/resolve/DolbyVision \
          "opt/resolve/Apple Immersive" \
          "opt/resolve/Apple Immersive/Calibration" 2>/dev/null || true
chmod -R 777 var/BlackmagicDesign 2>/dev/null || true
