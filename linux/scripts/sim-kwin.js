"use strict";

var SIM_CYCLE_MILLISECONDS = __SIM_CYCLE_MILLISECONDS__;
var simApps = [];
var simNextIndex = 0;
var simTimer = null;

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
