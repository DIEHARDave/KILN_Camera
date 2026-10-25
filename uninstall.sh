#!/bin/sh
# KILN_Camera: remove the root part (install.sh), as root:
#   sh /data/ad5x/plugins/camera/uninstall.sh
# The cameras go back to Kiln's defaults (camera.conf's own settings).
# Then DISABLE_PLUGIN NAME=camera and delete /data/ad5x/plugins/camera.
HOOK=/data/ad5x/camera-hook.sh
CAM_CONF=/data/ad5x/camera.conf
WATCH_PID=/run/ad5x-camera-watch.pid

[ "$(id -u)" = 0 ] || { echo "uninstall.sh: run as root"; exit 1; }
start-stop-daemon -K -q -p $WATCH_PID 2>/dev/null
rm -f $WATCH_PID
# screen.conf now, camera.conf from hook version 1; camera.conf also
# holds the settings block the hook writes
for CONF in /data/ad5x/screen.conf $CAM_CONF; do
	[ -f $CONF ] || continue
	sed -i -e '/^# KILN_Camera plugin/d' -e "\\|^\\. $HOOK\$|d" \
		-e '/^# KILN_Camera settings, /,/^# KILN_Camera end$/d' $CONF
	# nothing left but comments and blank lines: it was ours
	grep -qv '^[[:space:]]*\(#.*\)\{0,1\}$' $CONF || rm -f $CONF
done
rm -f $HOOK
/etc/init.d/S64ad5x-camera restart
echo "KILN_Camera root part removed"
