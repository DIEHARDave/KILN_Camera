#!/bin/sh
# KILN_Camera: the root part (a plugin runs as user klipper and can't).
# Run once as root after cloning, and again when CAMERA_STATUS says the
# hook is outdated:
#   sh /data/ad5x/plugins/camera/install.sh
# Copies root/camera-hook.sh to /data/ad5x/camera-hook.sh (root-owned, so
# the clone that Moonraker updates as klipper is never run as root),
# adds its line to /data/ad5x/screen.conf (sourced as root at every boot
# by Kiln's screen service) and runs it, which writes the settings into
# camera.conf and starts the watcher. A stopgap: Kiln has no boot hook
# for plugins, and since v0.0.24 camera.conf (used before) is not run.
set -e
HOOK=/data/ad5x/camera-hook.sh
CONF=/data/ad5x/screen.conf
OLD_CONF=/data/ad5x/camera.conf
WATCH_PID=/run/ad5x-camera-watch.pid
SERVICE=/etc/init.d/S65ad5x-screen
LINE=". $HOOK"
D=$(cd "$(dirname "$0")" && pwd)

[ "$(id -u)" = 0 ] || { echo "install.sh: run as root"; exit 1; }
grep -qs '^[[:space:]]*\[ -f \$CONF \] && \. \$CONF' $SERVICE &&
	grep -qs "^CONF=$CONF\$" $SERVICE || {
	echo "install.sh: $SERVICE missing or doesn't source $CONF;"
	echo "this Kiln OS has no hook left to use (see README)"
	exit 1
}

cp "$D/root/camera-hook.sh" $HOOK.new
chown root:root $HOOK.new
chmod 755 $HOOK.new
mv $HOOK.new $HOOK
echo "installed $HOOK (version $(sed -n 's/^CAM_HOOK_VERSION=//p' $HOOK))"

# Hook version 1 was sourced from camera.conf, which Kiln now reads as
# settings only (and logs our line as skipped)
if grep -qxF "$LINE" $OLD_CONF 2>/dev/null; then
	sed -i -e '/^# KILN_Camera plugin/d' -e "\\|^\\. $HOOK\$|d" $OLD_CONF
	echo "removed the old hook line from $OLD_CONF"
fi

if ! grep -qxF "$LINE" $CONF 2>/dev/null; then
	[ -f $CONF ] && cp -p $CONF $CONF.before-kiln-camera
	printf '# KILN_Camera plugin (uninstall.sh removes these two lines)\n%s\n' \
		"$LINE" >> $CONF
	echo "added the hook to $CONF"
fi
# Kiln runs with umask 077: let Klipper (CAMERA_STATUS) read it
chown root:root $CONF
chmod 644 $CONF

# The watcher runs the old code: stop it, the hook starts the new one
# (and restarts the cameras if their settings changed)
start-stop-daemon -K -q -p $WATCH_PID 2>/dev/null || true
rm -f $WATCH_PID
sh $HOOK
echo "camera settings in $OLD_CONF, watcher started"
