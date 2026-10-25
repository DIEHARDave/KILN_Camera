# KILN_Camera: state of the root hook (install.sh) that CAMERA_ON /
# CAMERA_OFF / CAMERA_RESTART (plugin.cfg) rely on, CAMERA_STATUS, and a
# console warning when the hook is missing, outdated or not running.
#
# Klipper runs as user klipper: this module only reads files. The
# cameras are started by Kiln's S64ad5x-camera (root) from
# /data/ad5x/camera.conf; the hook, sourced by S65ad5x-screen through
# /data/ad5x/screen.conf, writes the settings there.
#
# Copyright (C) 2026  DIEHARDave
#
# This file may be distributed under the terms of the GNU GPLv3 license.
import logging
import os
import re

HOOK = "/data/ad5x/camera-hook.sh"
CONF = "/data/ad5x/screen.conf"
V4L = "/sys/class/video4linux"
VERSION_RE = re.compile(r"^CAM_HOOK_VERSION=(\d+)", re.M)
CHECK_INTERVAL = 30.
INSTALL = "sh /data/ad5x/plugins/camera/install.sh"

def hook_version(path):
    """CAM_HOOK_VERSION of a hook file; None if unreadable, 0 if absent."""
    try:
        with open(path) as f:
            m = VERSION_RE.search(f.read())
    except OSError:
        return None
    return int(m.group(1)) if m else 0

def processes():
    """Command lines (argument lists) of all processes. Kiln runs with
    umask 077, so root's pid files can't be read; /proc cmdlines can."""
    out = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open("/proc/%s/cmdline" % (pid,), "rb") as f:
                args = f.read().split(b"\0")
        except OSError:
            continue
        out.append([a.decode("utf-8", "replace") for a in args if a])
    return out

def watcher_running(procs):
    return any(HOOK in args and "watch" in args for args in procs)

def stream_count(procs):
    return len([args for args in procs
                if args and os.path.basename(args[0]) == "ustreamer"])

def cameras():
    """Names of the UVC capture nodes (index 0), like S64ad5x-camera."""
    out = []
    try:
        nodes = sorted(os.listdir(V4L))
    except OSError:
        return out
    for node in nodes:
        d = os.path.join(V4L, node)
        try:
            with open(os.path.join(d, "index")) as f:
                if f.read().strip() != "0":
                    continue
            driver = os.path.basename(os.path.realpath(
                os.path.join(d, "device", "driver")))
            with open(os.path.join(d, "name")) as f:
                name = f.read().strip()
        except OSError:
            continue
        if driver == "uvcvideo":
            out.append("%s (%s)" % (node, name))
    return out

class KilnCamera:
    def __init__(self, config):
        self.printer = config.get_printer()
        self.reactor = self.printer.get_reactor()
        plugin_dir = os.path.dirname(os.path.dirname(
            os.path.realpath(__file__)))
        self.plugin_hook = os.path.join(plugin_dir, "root", "camera-hook.sh")
        self.problems = []
        self.printer.register_event_handler("klippy:ready", self._ready)
        gcode = self.printer.lookup_object('gcode')
        gcode.register_command("CAMERA_STATUS", self.cmd_CAMERA_STATUS,
                               desc="Camera hook, cameras and streams")
    def _check(self):
        problems = []
        installed = hook_version(HOOK)
        wanted = hook_version(self.plugin_hook) or 0
        try:
            with open(CONF) as f:
                sourced = (". " + HOOK) in f.read().splitlines()
        except OSError:
            sourced = False
        if installed is None or not sourced:
            problems.append("camera hook not installed: run as root: "
                            + INSTALL)
        elif installed < wanted:
            problems.append("camera hook outdated (v%d, plugin has v%d):"
                            " run as root: %s" % (installed, wanted, INSTALL))
        elif not watcher_running(processes()):
            problems.append("camera watcher not running: run as root:"
                            " sh " + HOOK)
        self.problems = problems
        return problems
    def _ready(self):
        if self._check():
            msg = "KILN_Camera: " + "; ".join(self.problems)
            logging.warning(msg)
            self.printer.lookup_object('gcode').respond_info("!! " + msg)
        self.reactor.register_timer(self._timer,
                                    self.reactor.monotonic() + CHECK_INTERVAL)
    def _timer(self, eventtime):
        self._check()
        return eventtime + CHECK_INTERVAL
    def get_status(self, eventtime):
        return {'problems': list(self.problems)}
    def cmd_CAMERA_STATUS(self, gcmd):
        self._check()
        sv = self.printer.lookup_object('save_variables', None)
        saved = sv.allVariables if sv is not None else {}
        cams = cameras()
        procs = processes()
        streams = stream_count(procs)
        installed = hook_version(HOOK)
        lines = [
            "Hook: %s" % ("v%d" % installed if installed is not None
                          else "not installed"),
            "Watcher: %s" % ("running" if watcher_running(procs)
                             else "not running"),
            "Settings: %s, %s at %s fps" % (
                "off" if saved.get('camera_on', 1) in (0, False) else "on",
                saved.get('camera_resolution', "1280x720"),
                saved.get('camera_fps', 15)),
            "Cameras: %s" % (", ".join(cams) or "none"),
            "Streams running: %d (/webcam/%s)" % (
                streams, ", /webcam2/ ..." if streams > 1 else "")]
        lines += ["!! " + p for p in self.problems]
        gcmd.respond_info("\n".join(lines))

def load_config(config):
    return KilnCamera(config)
