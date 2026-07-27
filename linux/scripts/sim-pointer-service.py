#!/usr/bin/env python3

import os
import signal
import subprocess
import sys
import time
import warnings

import gi

warnings.filterwarnings("ignore", category=DeprecationWarning)
gi.require_version("Gio", "2.0")
from gi.repository import Gio, GLib


OBJECT_PATH = "/io/github/AndiOliverIon/MacForge/Sim"
INTERFACE = "io.github.AndiOliverIon.MacForge.Sim"
INTROSPECTION_XML = f"""
<node>
  <interface name="{INTERFACE}">
    <method name="Move">
      <arg type="i" name="original_x" direction="in"/>
      <arg type="i" name="original_y" direction="in"/>
      <arg type="i" name="target_x" direction="in"/>
      <arg type="i" name="target_y" direction="in"/>
      <arg type="i" name="horizontal_x" direction="in"/>
      <arg type="i" name="horizontal_y" direction="in"/>
      <arg type="i" name="vertical_x" direction="in"/>
      <arg type="i" name="vertical_y" direction="in"/>
      <arg type="b" name="success" direction="out"/>
    </method>
  </interface>
</node>
"""


def die(message):
    print(f"Error: {message}", file=sys.stderr, flush=True)
    raise SystemExit(1)


if len(sys.argv) != 3:
    die("sim pointer service requires a D-Bus service name and parent PID.")

service_name = sys.argv[1]
try:
    parent_pid = int(sys.argv[2])
except ValueError:
    die("sim pointer service received an invalid parent PID.")

node_info = Gio.DBusNodeInfo.new_for_xml(INTROSPECTION_XML)
loop = GLib.MainLoop()
bus_connection = None
input_device_path = None
original_flat_profile = None
original_adaptive_profile = None


def dbus_property_get(connection, path, name):
    result = connection.call_sync(
        "org.kde.KWin",
        path,
        "org.freedesktop.DBus.Properties",
        "Get",
        GLib.Variant("(ss)", ("org.kde.KWin.InputDevice", name)),
        GLib.VariantType.new("(v)"),
        Gio.DBusCallFlags.NONE,
        -1,
        None,
    )
    return result.unpack()[0]


def dbus_property_set(connection, path, name, value):
    connection.call_sync(
        "org.kde.KWin",
        path,
        "org.freedesktop.DBus.Properties",
        "Set",
        GLib.Variant(
            "(ssv)",
            (
                "org.kde.KWin.InputDevice",
                name,
                GLib.Variant("b", value),
            ),
        ),
        None,
        Gio.DBusCallFlags.NONE,
        -1,
        None,
    )


def find_ydotool_device(connection):
    result = connection.call_sync(
        "org.kde.KWin",
        "/org/kde/KWin/InputDevice",
        "org.freedesktop.DBus.Introspectable",
        "Introspect",
        None,
        GLib.VariantType.new("(s)"),
        Gio.DBusCallFlags.NONE,
        -1,
        None,
    )
    input_devices = Gio.DBusNodeInfo.new_for_xml(result.unpack()[0])

    for child in input_devices.nodes:
        path = f"/org/kde/KWin/InputDevice/{child.path}"
        if dbus_property_get(connection, path, "name") == "ydotoold virtual device":
            return path

    raise RuntimeError("KWin does not expose the ydotoold virtual input device")


def configure_flat_profile(connection):
    global input_device_path
    global original_flat_profile
    global original_adaptive_profile

    input_device_path = find_ydotool_device(connection)
    supports_flat = dbus_property_get(
        connection,
        input_device_path,
        "supportsPointerAccelerationProfileFlat",
    )
    if not supports_flat:
        raise RuntimeError("the ydotoold virtual device does not support a flat pointer profile")

    original_flat_profile = dbus_property_get(
        connection,
        input_device_path,
        "pointerAccelerationProfileFlat",
    )
    original_adaptive_profile = dbus_property_get(
        connection,
        input_device_path,
        "pointerAccelerationProfileAdaptive",
    )

    dbus_property_set(
        connection,
        input_device_path,
        "pointerAccelerationProfileAdaptive",
        False,
    )
    dbus_property_set(
        connection,
        input_device_path,
        "pointerAccelerationProfileFlat",
        True,
    )


def restore_pointer_profile():
    if bus_connection is None or input_device_path is None:
        return

    try:
        dbus_property_set(
            bus_connection,
            input_device_path,
            "pointerAccelerationProfileFlat",
            original_flat_profile,
        )
        dbus_property_set(
            bus_connection,
            input_device_path,
            "pointerAccelerationProfileAdaptive",
            original_adaptive_profile,
        )
    except GLib.Error as error:
        print(
            f"Error: could not restore the ydotool pointer profile: {error}",
            file=sys.stderr,
            flush=True,
        )


def move_pointer(x, y):
    subprocess.run(
        ["ydotool", "mousemove", "-x", str(x), "-y", str(y)],
        check=True,
    )


def stop_parent(message):
    print(f"Error: {message}; stopping sim.", file=sys.stderr, flush=True)
    try:
        os.kill(parent_pid, signal.SIGTERM)
    except ProcessLookupError:
        pass


def handle_method_call(
    connection,
    sender,
    object_path,
    interface_name,
    method_name,
    parameters,
    invocation,
):
    if method_name != "Move":
        invocation.return_dbus_error(
            f"{INTERFACE}.UnknownMethod",
            f"Unknown method: {method_name}",
        )
        return

    (
        original_x,
        original_y,
        target_x,
        target_y,
        horizontal_x,
        horizontal_y,
        vertical_x,
        vertical_y,
    ) = parameters
    moved = False

    try:
        move_pointer(-100000, -100000)
        move_pointer(target_x, target_y)
        moved = True
        time.sleep(0.25)
        move_pointer(horizontal_x - target_x, horizontal_y - target_y)
        time.sleep(0.25)
        move_pointer(vertical_x - horizontal_x, vertical_y - horizontal_y)
        time.sleep(0.25)
        move_pointer(-100000, -100000)
        move_pointer(original_x, original_y)
    except (OSError, subprocess.CalledProcessError) as error:
        if moved:
            try:
                move_pointer(-100000, -100000)
                move_pointer(original_x, original_y)
            except (OSError, subprocess.CalledProcessError):
                pass
        invocation.return_value(GLib.Variant("(b)", (False,)))
        stop_parent(f"ydotool failed while moving the pointer: {error}")
        return

    invocation.return_value(GLib.Variant("(b)", (True,)))


def on_bus_acquired(connection, name):
    global bus_connection
    bus_connection = connection

    try:
        configure_flat_profile(connection)
        connection.register_object(
            OBJECT_PATH,
            node_info.interfaces[0],
            handle_method_call,
            None,
            None,
        )
    except (GLib.Error, RuntimeError) as error:
        stop_parent(f"could not configure ydotool for deterministic movement: {error}")
        loop.quit()


def on_name_lost(connection, name):
    die(f"could not own the private D-Bus service name {name}.")


def stop_service(signum, frame):
    loop.quit()


Gio.bus_own_name(
    Gio.BusType.SESSION,
    service_name,
    Gio.BusNameOwnerFlags.NONE,
    on_bus_acquired,
    None,
    on_name_lost,
)
signal.signal(signal.SIGINT, stop_service)
signal.signal(signal.SIGTERM, stop_service)

try:
    loop.run()
finally:
    restore_pointer_profile()
