#!/bin/sh
# KILN_Camera: the root part (a plugin runs as user klipper and can't).
# Run once as root after cloning, and again when CAMERA_STATUS says the
# hook is outdated:
#   sh /data/ad5x/plugins/camera/install.sh
# Copies root/camera-hook.sh to /data/ad5x/camera-hook.sh (root-owned, so
# the clone that Moonraker updates as klipper is never run as root),
# adds its line to /data/ad5x/camera.conf and restarts the cameras.
set -e
HOOK=/data/ad5x/camera-hook.sh
CONF=/data/ad5x/camera.conf
WATCH_PID=/run/ad5x-camera-watch.pid
SERVICE=/etc/init.d/S64ad5x-camera
LINE=". $HOOK"
D=$(cd "$(dirname "$0")" && pwd)

[ "$(id -u)" = 0 ] || { echo "install.sh: run as root"; exit 1; }
grep -qs "$CONF" $SERVICE || {
	echo "install.sh: $SERVICE missing or doesn't read $CONF (not Kiln OS?)"
	exit 1
}

cp "$D/root/camera-hook.sh" $HOOK.new
chown root:root $HOOK.new
chmod 755 $HOOK.new
mv $HOOK.new $HOOK
echo "installed $HOOK (version $(sed -n 's/^CAM_HOOK_VERSION=//p' $HOOK))"

if ! grep -qxF "$LINE" $CONF 2>/dev/null; then
	[ -f $CONF ] && cp -p $CONF $CONF.before-kiln-camera
	printf '# KILN_Camera plugin (uninstall.sh removes these two lines)\n%s\n' \
		"$LINE" >> $CONF
	echo "added the hook to $CONF"
fi
# Kiln runs with umask 077: let Klipper (CAMERA_STATUS) read it
chmod 644 $CONF

# The watcher runs the old code: stop it, the restart starts the new one
start-stop-daemon -K -q -p $WATCH_PID 2>/dev/null || true
rm -f $WATCH_PID
$SERVICE restart
