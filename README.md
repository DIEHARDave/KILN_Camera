# KILN_Camera

A [Kiln OS](https://github.com/djvalic/kiln-os) plugin for the Flashforge
AD5X that adds zMod's camera macros and camera hotplug:

```
CAMERA_ON                               on, with the last settings
CAMERA_ON WIDTH=1920 HEIGHT=1080 FPS=15 settings are kept across reboots
CAMERA_OFF                              stays off across reboots
CAMERA_RESTART
CAMERA_STATUS                           hook, cameras, streams
```

Kiln OS already streams USB cameras: its `S64ad5x-camera` service runs
one ustreamer per UVC camera, behind nginx at `/webcam/`, `/webcam2/`, ...
(Fluidd and HelixScreen list them). This plugin doesn't replace that; it
adds:

- **The zMod macro names**, so habits and macros from zMod keep working.
  zMod's `VIDEO=`, `STREAMER=`, `FORMAT=` and `FS=` are accepted and
  ignored: every UVC camera is streamed, as MJPEG by ustreamer.
- **Hotplug.** Kiln looks for cameras only at boot, so a camera plugged
  in later stays dark until a reboot. With this plugin it starts within
  about 6 seconds, and an unplugged one is stopped.

Defaults (nothing saved yet): 1280x720 at 15 fps, Kiln's own defaults.

## Install

Two parts: the plugin itself (runs as user `klipper`), and a small root
hook that a plugin can't install by itself. Over SSH as root (Kiln's
default password is `root`):

```sh
cd /data/ad5x/plugins
su klipper -s /bin/sh -c 'git clone https://github.com/DIEHARDave/KILN_Camera.git camera'
sh /data/ad5x/plugins/camera/install.sh
```

Then in the console (Fluidd, HelixScreen or a macro):

```
ENABLE_PLUGIN NAME=camera
```

This restarts Klipper, and Moonraker picks up the update entry. Run
`CAMERA_STATUS` to check: it should say `Hook: v1` and `Watcher:
running`. Whenever the hook is missing, outdated or not running, the
console shows a `KILN_Camera:` warning with the command that fixes it.

## Updates

Fluidd > Settings > Software Updates lists `kiln-camera`. After an
update, `RESTART` Klipper. If `CAMERA_STATUS` then says the hook is
outdated, run `install.sh` again as root.

## How it works

Kiln's system partition is read-only and Klipper can't run shell
commands, but `S64ad5x-camera` (root) sources `/data/ad5x/camera.conf`
on the data partition when it starts. `install.sh`:

1. copies `root/camera-hook.sh` to `/data/ad5x/camera-hook.sh`, owned by
   root. The clone in `/data/ad5x/plugins/camera` belongs to `klipper`,
   so root never runs code from it; that's why an update needs
   `install.sh` again.
2. adds `. /data/ad5x/camera-hook.sh` to `/data/ad5x/camera.conf`
   (a copy of an existing file is kept as `camera.conf.before-kiln-camera`).
3. restarts the cameras.

When the camera service starts, the hook:

- reads the `camera_on`, `camera_resolution` and `camera_fps` variables
  that the macros save with `SAVE_VARIABLE` in Klipper's `variables.cfg`.
  The values are parsed and checked, never run: that file is writable by
  `klipper`.
- starts a watcher (once per boot) that checks every 3 seconds whether
  a camera was plugged in or out, or whether a `camera_*` variable
  changed (`CAMERA_RESTART` bumps `camera_restart`). If so, it restarts
  the camera service. It logs to `/var/log/messages` with the tag
  `ad5x-camera`.

Settings written in `camera.conf` by hand (`RESOLUTION_2=`, ...) still
work. A setting saved by a macro wins over the same one written above the
hook's line.

## A second camera slot that says "error"

Kiln's default `moonraker.conf` lists two cameras, `camera1`
(`/webcam/`) and `camera2` (`/webcam2/`). With one camera, Fluidd shows
`camera2` as an error. To hide it, add `enabled: False` under
`[webcam camera2]` in `moonraker.conf` and restart Moonraker. Set it back
to `True` when you plug in a second camera.

## Uninstall

As root:

```sh
sh /data/ad5x/plugins/camera/uninstall.sh
```

Then `DISABLE_PLUGIN NAME=camera` and delete `/data/ad5x/plugins/camera`.
The cameras go back to Kiln's defaults. The `camera_*` variables stay in
`variables.cfg` but nothing reads them.

## License

GPLv3, like Klipper and Kiln OS.
