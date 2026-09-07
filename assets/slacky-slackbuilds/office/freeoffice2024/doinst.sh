# Clean up obsolete legacy manual installer desktop files
rm -f usr/share/applications/freeoffice-textmaker.desktop \
      usr/share/applications/freeoffice-planmaker.desktop \
      usr/share/applications/freeoffice-presentations.desktop

# Clean up obsolete manual symlinks in /usr/local/bin if pointing to old manual install
for b in textmaker planmaker presentations; do
  if [ -L usr/local/bin/$b ]; then
    rm -f usr/local/bin/$b
  fi
done

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
