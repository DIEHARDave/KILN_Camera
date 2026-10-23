#!/bin/sh
#####################################################################
# KILN_Camera root hook: camera settings + hotplug for Kiln OS (AD5X)
#
# install.sh copies this to /data/ad5x/camera-hook.sh (root) and adds
#   . /data/ad5x/camera-hook.sh
# to /data/ad5x/camera.conf, which Kiln's /etc/init.d/S64ad5x-camera
# (root) sources in start(). When sourced, this hook:
#   - applies the settings CAMERA_ON / CAMERA_OFF (plugin.cfg) keep in
#     Klipper's variables.cfg. They are parsed and checked, never
#     sourced: that file is writable by user klipper.
#   - starts the watcher once (pid in /run, so once per boot)
# The watcher ("camera-hook.sh watch") restarts the camera service when a
# camera is plugged in or out, or when a camera_* variable changes
# (CAMERA_RESTART bumps camera_restart). Kiln itself scans only at boot.
#####################################################################

# Bump when this file changes: the plugin's CAMERA_STATUS compares it
# with the installed copy and asks for install.sh again
CAM_HOOK_VERSION=1

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

cam_watch() {
	last=$(cam_state)
	while sleep 3; do
		[ "$(cam_state)" = "$last" ] && continue
		# let a camera finish enumerating (two video nodes appear)
		sleep 3
		last=$(cam_state)
		logger -t ad5x-camera "change seen, restarting cameras"
		$CAM_SERVICE restart 2>&1 | logger -t ad5x-camera
	done
}

if [ "$1" = watch ]; then
	cam_watch
	exit 0
fi

# Sourced by S64ad5x-camera start(): CAMERA, RESOLUTION, FPS hold its
# defaults; override them from the macros' variables
cam_v=$(cam_var camera_on)
case "$cam_v" in 0|False) CAMERA=off ;; 1|True) CAMERA=on ;; esac
cam_v=$(cam_var camera_resolution)
echo "$cam_v" | grep -qx '[0-9]\{3,4\}x[0-9]\{3,4\}' && RESOLUTION=$cam_v
cam_v=$(cam_var camera_fps)
echo "$cam_v" | grep -qx '[1-9][0-9]\{0,1\}' && FPS=$cam_v

if ! { [ -f $CAM_WATCH_PID ] && kill -0 "$(cat $CAM_WATCH_PID)" 2>/dev/null; }; then
	start-stop-daemon -S -b -m -p $CAM_WATCH_PID -x /bin/sh -- $CAM_HOOK watch
fi
