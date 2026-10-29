# KILN_Camera

A [Kiln OS](https://github.com/djvalic/kiln-os) plugin for the Flashforge
AD5X that adds zMod's camera macros and camera hotplug:

> **The boot hook is a stopgap.** This plugin needs a root boot hook,
> and Kiln OS has none for plugins. `camera.conf`, used before, has been
> read as settings only since Kiln v0.0.24, so `install.sh` now uses
> `/data/ad5x/screen.conf`, which Kiln's screen service still runs as a
> shell script at boot. A later Kiln release may close that too; then
> run `sh /data/ad5x/camera-hook.sh` as root after each reboot. A proper
> hook was requested in
> [djvalic/kiln-os#13](https://github.com/djvalic/kiln-os/issues/13).
> Installed before this change? `CAMERA_STATUS` says the hook is
> outdated: run `install.sh` again.

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
commands. `S64ad5x-camera` (root) reads its settings from
`/data/ad5x/camera.conf` (`CAMERA`, `RESOLUTION`, `FPS`, checked, never
run), and `S65ad5x-screen` (root) sources `/data/ad5x/screen.conf` as a
shell script when it starts. `install.sh`:

1. copies `root/camera-hook.sh` to `/data/ad5x/camera-hook.sh`, owned by
   root. The clone in `/data/ad5x/plugins/camera` belongs to `klipper`,
   so root never runs code from it; that's why an update needs
   `install.sh` again.
2. adds `. /data/ad5x/camera-hook.sh` to `/data/ad5x/screen.conf`
   (a copy of an existing file is kept as `screen.conf.before-kiln-camera`)
   and removes the line hook version 1 put in `camera.conf`.
3. runs the hook.

At boot (and when `install.sh` runs it), the hook:

- reads the `camera_on`, `camera_resolution` and `camera_fps` variables
  that the macros save with `SAVE_VARIABLE` in Klipper's `variables.cfg`.
  The values are parsed and checked, never run: that file is writable by
  `klipper`. It writes them into a marked block at the end of
  `camera.conf` and restarts the cameras if the block changed.
- starts a watcher (once per boot) that checks every 3 seconds whether
  a camera was plugged in or out, or whether a `camera_*` variable
  changed (`CAMERA_RESTART` bumps `camera_restart`). If so, it updates
  the block and restarts the camera service. It logs to
  `/var/log/messages` with the tag `ad5x-camera`.

Settings written in `camera.conf` by hand (`RESOLUTION_2=`, ...) still
work; keep them above the `# KILN_Camera settings` block. A setting saved
by a macro wins over the same one written by hand.

## Extra cameras listed (`camera1`, `camera2`)

Kiln's camera service now adds each camera to Moonraker by itself at
boot: the first as `Chamber/Bed`, the next ones as `Camera 2`, ... This
plugin doesn't add or change any webcam entries.

Older Kiln versions instead put `[webcam camera1]` (`/webcam/`) and
`[webcam camera2]` (`/webcam2/`) in `moonraker.conf`. Kiln only writes
that file when it's missing, so after an update those sections stay and
Fluidd lists the same camera twice, plus `camera2` as an error. Delete
both sections from `/home/klipper/printer_data/config/moonraker.conf` and
restart Moonraker.

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
