#!/bin/sh
#####################################################################
# KILN_Camera root hook: camera settings + hotplug for Kiln OS (AD5X)
#
# install.sh copies this to /data/ad5x/camera-hook.sh (root) and adds
#   . /data/ad5x/camera-hook.sh
# to /data/ad5x/screen.conf, which Kiln's /etc/init.d/S65ad5x-screen
# (root) sources at every boot. A stopgap: Kiln has no plugin boot hook,
# and since v0.0.24 camera.conf (used up to version 1) is read as
# settings only. When sourced, this hook:
#   - writes the settings CAMERA_ON / CAMERA_OFF (plugin.cfg) keep in
#     Klipper's variables.cfg into a marked block at the end of
#     /data/ad5x/camera.conf, as the KEY=value lines Kiln reads, and
#     restarts the cameras if the block changed. variables.cfg is
#     writable by user klipper: it is parsed and checked, never sourced.
#   - starts the watcher once (pid in /run, so once per boot)
# The watcher ("camera-hook.sh watch") does the same and restarts the
# camera service when a camera is plugged in or out, or when a camera_*
# variable changes (CAMERA_RESTART bumps camera_restart). Kiln itself
# scans only at boot.
# Kiln v0.0.25's camera service checks camera.conf's owner with "stat",
# which the image doesn't have, so it never reads the file. Until it
# does, the hook's own camera restarts get a python3 "stat" (in /run,
# first on PATH), and at boot, when camera.conf holds anything but the
# defaults, the hook restarts the cameras once with it.
# Names are prefixed (cam_): it runs inside S65ad5x-screen's start(),
# which has its own FPS.
#####################################################################

# Bump when this file changes: the plugin's CAMERA_STATUS compares it
# with the installed copy and asks for install.sh again
CAM_HOOK_VERSION=2

CAM_CONF=/data/ad5x/camera.conf
CAM_BEGIN="# KILN_Camera settings, from CAMERA_ON and CAMERA_OFF (the hook rewrites them)"
CAM_END="# KILN_Camera end"
CAM_SHIM=/run/kiln-camera-bin
CAM_VARS=/home/klipper/printer_data/config/variables.cfg
CAM_HOOK=/data/ad5x/camera-hook.sh
CAM_WATCH_PID=/run/ad5x-camera-watch.pid
CAM_SERVICE=/etc/init.d/S64ad5x-camera

# cam_var NAME: a save_variables value, quotes stripped
cam_var() {
	awk -F' = ' -v n="$1" '$1 == n {
		v = $2; gsub(/^["\047]|["\047]$/, "", v); print v; exit
	}' $CAM_VARS 2>/dev/null
}

# What the watcher compares: video nodes present + the camera_* variables
cam_state() {
	ls -d /sys/class/video4linux/video* 2>/dev/null | tr '\n' ' '
	grep '^camera_' $CAM_VARS 2>/dev/null
}

# cam_settings: the KEY=value lines for camera.conf, checked like Kiln
# does (a value that isn't valid is left out: Kiln's default applies)
cam_settings() {
	cam_v=$(cam_var camera_on)
	case "$cam_v" in 0|False) echo CAMERA=off ;; 1|True) echo CAMERA=on ;; esac
	cam_v=$(cam_var camera_resolution)
	echo "$cam_v" | grep -qx '[0-9]\{3,4\}x[0-9]\{3,4\}' && echo "RESOLUTION=$cam_v"
	cam_v=$(cam_var camera_fps)
	echo "$cam_v" | grep -qx '[1-9][0-9]\{0,1\}' && [ "$cam_v" -le 60 ] && echo "FPS=$cam_v"
}

# cam_write: camera.conf with our block brought up to date (hand-written
# lines kept; ours last, so they win). True when the file changed. Kiln
# reads it only if owned by root and not writable by group or others.
cam_write() {
	cam_new=$CAM_CONF.kiln-camera
	{
		[ -f $CAM_CONF ] && sed -e "/^$CAM_BEGIN\$/,/^$CAM_END\$/d" $CAM_CONF
		cam_s=$(cam_settings)
		[ -n "$cam_s" ] && printf '%s\n%s\n%s\n' "$CAM_BEGIN" "$cam_s" "$CAM_END"
	} > $cam_new
	if cmp -s $cam_new $CAM_CONF 2>/dev/null ||
	   { [ ! -f $CAM_CONF ] && [ ! -s $cam_new ]; }; then
		rm -f $cam_new
		return 1
	fi
	chown root:root $cam_new
	chmod 644 $cam_new
	mv $cam_new $CAM_CONF
	return 0
}

# cam_shim: true when Kiln has no stat and the python3 one is in place
cam_shim() {
	command -v stat >/dev/null 2>&1 && return 1
	[ -x $CAM_SHIM/stat ] && return 0
	mkdir -p $CAM_SHIM
	cat > $CAM_SHIM/stat <<'CAM_EOF'
#!/usr/bin/python3
# KILN_Camera: what S64ad5x-camera's load_conf calls, stat -c %u|%A FILE
import os, stat, sys
a = sys.argv[1:]
if len(a) != 3 or a[0] != "-c" or a[1] not in ("%u", "%A"):
    sys.exit("stat: only -c %u|%A FILE")
st = os.stat(a[2])
print(st.st_uid if a[1] == "%u" else stat.filemode(st.st_mode))
CAM_EOF
	chmod 755 $CAM_SHIM $CAM_SHIM/stat
}

cam_restart() {
	cam_shim
	PATH=$CAM_SHIM:$PATH $CAM_SERVICE restart 2>&1 | logger -t ad5x-camera
}

# cam_custom: camera.conf sets something other than Kiln's defaults
cam_custom() {
	grep -v -e '^#' -e '^[[:space:]]*$' $CAM_CONF 2>/dev/null |
		grep -qvx -e CAMERA=on -e RESOLUTION=1280x720 -e FPS=15
}

cam_watch() {
	last=$(cam_state)
	while sleep 3; do
		[ "$(cam_state)" = "$last" ] && continue
		# let a camera finish enumerating (two video nodes appear)
		sleep 3
		last=$(cam_state)
		logger -t ad5x-camera "change seen, restarting cameras"
		cam_write
		cam_restart
	done
}

if [ "$1" = watch ]; then
	cam_watch
	exit 0
fi

# Sourced at boot (or run by install.sh): S64ad5x-camera has already
# started the cameras from camera.conf, so restart only if it changed,
# or, the first time this boot, if Kiln couldn't read it (no stat) and
# it isn't all defaults. In the background: the camera service waits
# for Moonraker.
if { [ -f $CAM_WATCH_PID ] && kill -0 "$(cat $CAM_WATCH_PID)" 2>/dev/null; }; then
	cam_first=0
else
	cam_first=1
fi
if cam_write; then
	logger -t ad5x-camera "settings changed, restarting cameras"
	cam_restart &
elif [ $cam_first = 1 ] && ! command -v stat >/dev/null 2>&1 && cam_custom; then
	logger -t ad5x-camera "Kiln can't read camera.conf (no stat), restarting cameras"
	cam_restart &
fi

if [ $cam_first = 1 ]; then
	start-stop-daemon -S -b -m -p $CAM_WATCH_PID -x /bin/sh -- $CAM_HOOK watch
fi
