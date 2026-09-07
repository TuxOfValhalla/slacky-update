config() {
  NEW="$1"
  OLD="$(dirname $NEW)/$(basename $NEW .new)"
  # If there's no config file by that name, mv it over:
  if [ ! -r $OLD ]; then
    mv $NEW $OLD
  elif [ "$(cat $OLD | md5sum)" = "$(cat $NEW | md5sum)" ]; then
    # toss the redundant copy
    rm $NEW
  fi
  # Otherwise, we leave the .new copy for the admin to consider...
}

config etc/snapper/snapper.new
config etc/snapper/configs/root.new
config etc/cron.hourly/snapper-cleanup.new
config etc/cron.hourly/snapper-timeline.new

# Ensure /.snapshots permissions are aligned with wheel group
if [ -d /.snapshots ]; then
  chmod 750 /.snapshots 2>/dev/null || true
  chgrp wheel /.snapshots 2>/dev/null || true
fi
