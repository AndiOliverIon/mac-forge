"use strict";

var SIM_CYCLE_MILLISECONDS = __SIM_CYCLE_MILLISECONDS__;
var SIM_DBUS_SERVICE = "__SIM_DBUS_SERVICE__";
var SIM_DBUS_PATH = "/io/github/AndiOliverIon/MacForge/Sim";
var SIM_DBUS_INTERFACE = "io.github.AndiOliverIon.MacForge.Sim";
var simApps = [];
var simNextIndex = 0;
var simTimer = null;
var simActivationTimers = [];
var SIM_ACTIVATION_DELAY_MILLISECONDS = 200;
var SIM_MOUSE_MOVEMENT_PIXELS = 24;

function simWindowList() {
    if (typeof workspace.windowList === "function") {
        return workspace.windowList();
    }

    if (typeof workspace.clientList === "function") {
        return workspace.clientList();
    }

    if (workspace.stackingOrder) {
        return workspace.stackingOrder;
    }

    return [];
}

function simActiveWindow() {
    if (workspace.activeWindow !== undefined) {
        return workspace.activeWindow;
    }

    return workspace.activeClient;
}

function simAppKey(window) {
    return String(
        window.desktopFileName ||
        window.resourceClass ||
        window.resourceName ||
        window.pid ||
        window.caption
    );
}

function simAppLabel(window) {
    return String(
        window.desktopFileName ||
        window.resourceClass ||
        window.caption ||
        "unknown"
    );
}

function simEligibleAtStartup(window) {
    return window &&
        window.normalWindow === true &&
        window.managed !== false &&
        window.deleted !== true &&
        window.minimized !== true &&
        window.skipTaskbar !== true &&
        window.skipSwitcher !== true;
}

function simAvailableWindow(app) {
    for (var i = app.windows.length - 1; i >= 0; i--) {
        var window = app.windows[i];

        try {
            if (window &&
                window.deleted !== true &&
                window.managed !== false &&
                window.minimized !== true) {
                return window;
            }
        } catch (error) {
            print("sim: skipped unavailable window: " + error);
        }
    }

    return null;
}

function simAvailableAppCount() {
    var count = 0;

    for (var i = 0; i < simApps.length; i++) {
        if (simAvailableWindow(simApps[i])) {
            count++;
        }
    }

    return count;
}

function simActivate(window) {
    if (workspace.activeWindow !== undefined) {
        workspace.activeWindow = window;
    } else {
        workspace.activeClient = window;
    }

    if (typeof workspace.raiseWindow === "function") {
        workspace.raiseWindow(window);
    }
}

function simRoundedCoordinate(value) {
    return Math.round(Number(value));
}

function simMouseEvent(window) {
    var geometry = window.clientGeometry || window.frameGeometry;
    if (!geometry || geometry.width < 2 || geometry.height < 2) {
        throw new Error("focused window has no usable geometry");
    }

    var original = workspace.cursorPos;
    if (!original) {
        throw new Error("KWin did not provide the current pointer position");
    }

    var minX = Math.ceil(Number(geometry.x));
    var minY = Math.ceil(Number(geometry.y));
    var maxX = Math.floor(Number(geometry.x) + Number(geometry.width) - 1);
    var maxY = Math.floor(Number(geometry.y) + Number(geometry.height) - 1);
    var targetX = Math.max(minX, Math.min(maxX, simRoundedCoordinate(
        Number(geometry.x) + Number(geometry.width) / 2
    )));
    var targetY = Math.max(minY, Math.min(maxY, simRoundedCoordinate(
        Number(geometry.y) + Number(geometry.height) / 2
    )));
    var horizontalX = Math.min(maxX, targetX + SIM_MOUSE_MOVEMENT_PIXELS);
    var verticalY = Math.min(maxY, targetY + SIM_MOUSE_MOVEMENT_PIXELS);

    if (horizontalX === targetX) {
        horizontalX = Math.max(minX, targetX - SIM_MOUSE_MOVEMENT_PIXELS);
    }
    if (verticalY === targetY) {
        verticalY = Math.max(minY, targetY - SIM_MOUSE_MOVEMENT_PIXELS);
    }

    callDBus(
        SIM_DBUS_SERVICE,
        SIM_DBUS_PATH,
        SIM_DBUS_INTERFACE,
        "Move",
        simRoundedCoordinate(original.x),
        simRoundedCoordinate(original.y),
        targetX,
        targetY,
        horizontalX,
        targetY,
        horizontalX,
        verticalY,
        function(success) {
            if (success !== true) {
                print("sim: pointer service reported a movement failure");
            }
        }
    );
}

function simScheduleMouseEvent(window, appLabel) {
    var timer = new QTimer();
    timer.interval = SIM_ACTIVATION_DELAY_MILLISECONDS;
    timer.singleShot = true;
    simActivationTimers.push(timer);

    timer.timeout.connect(function() {
        var timerIndex = simActivationTimers.indexOf(timer);
        if (timerIndex !== -1) {
            simActivationTimers.splice(timerIndex, 1);
        }

        try {
            if (window.deleted !== true && window.minimized !== true) {
                simMouseEvent(window);
            }
        } catch (error) {
            print("sim: could not move pointer for " + appLabel + ": " + error);
        }
    });
    timer.start();
}

function simCycle() {
    if (simAvailableAppCount() < 2) {
        print("sim: waiting because fewer than two captured apps are available");
        return;
    }

    for (var attempts = 0; attempts < simApps.length; attempts++) {
        var app = simApps[simNextIndex];
        simNextIndex = (simNextIndex + 1) % simApps.length;

        var window = simAvailableWindow(app);
        if (!window) {
            continue;
        }

        try {
            simActivate(window);
            simScheduleMouseEvent(window, app.label);
        } catch (error) {
            print("sim: could not activate " + app.label + ": " + error);
        }
        return;
    }
}

function simCaptureApps() {
    var windows = simWindowList();
    var appIndexes = {};
    var activeWindow = simActiveWindow();
    var activeAppIndex = -1;

    for (var i = 0; i < windows.length; i++) {
        var window = windows[i];
        if (!simEligibleAtStartup(window)) {
            continue;
        }

        var key = "app:" + simAppKey(window);
        var index = appIndexes[key];

        if (index === undefined) {
            index = simApps.length;
            appIndexes[key] = index;
            simApps.push({
                key: key,
                label: simAppLabel(window),
                windows: []
            });
        }

        simApps[index].windows.push(window);
        if (window === activeWindow || window.active === true) {
            activeAppIndex = index;
        }
    }

    if (simApps.length < 2) {
        print("sim: at least two open, non-minimized apps are required; found " + simApps.length);
        return false;
    }

    simNextIndex = (activeAppIndex + 1 + simApps.length) % simApps.length;
    print(
        "sim: captured " + simApps.length + " apps: " +
        simApps.map(function(app) { return app.label; }).join(", ")
    );
    return true;
}

if (simCaptureApps()) {
    simTimer = new QTimer();
    simTimer.interval = SIM_CYCLE_MILLISECONDS;
    simTimer.singleShot = false;
    simTimer.timeout.connect(simCycle);
    simTimer.start();
}
