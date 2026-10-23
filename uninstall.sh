#!/bin/sh
# KILN_Camera: remove the root part (install.sh), as root:
#   sh /data/ad5x/plugins/camera/uninstall.sh
# The cameras go back to Kiln's defaults (camera.conf's own settings).
# Then DISABLE_PLUGIN NAME=camera and delete /data/ad5x/plugins/camera.
HOOK=/data/ad5x/camera-hook.sh
CONF=/data/ad5x/camera.conf
WATCH_PID=/run/ad5x-camera-watch.pid

[ "$(id -u)" = 0 ] || { echo "uninstall.sh: run as root"; exit 1; }
start-stop-daemon -K -q -p $WATCH_PID 2>/dev/null
rm -f $WATCH_PID
if [ -f $CONF ]; then
	sed -i -e '/^# KILN_Camera plugin/d' -e "\\|^\\. $HOOK\$|d" $CONF
	# nothing left but comments and blank lines: it was ours
	grep -qv '^[[:space:]]*\(#.*\)\{0,1\}$' $CONF || rm -f $CONF
fi
rm -f $HOOK
/etc/init.d/S64ad5x-camera restart
echo "KILN_Camera root part removed"
