pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property var info: ({})
    // The installer as it goes, for every place that shows it: the step it
    // reported last (starting, waiting, source, build, download, verify), how
    // it ended (installed, failed, cancelled; "" while running or before any),
    // and times in ms, so a long step can be seen to be still going.
    property string stage: ""
    property string outcome: ""
    property real bytes: 0
    property real total: 0
    property real stageSince: 0
    property real lastEvent: 0
    property real now: 0
    property string message: ""
    property string error: ""
    property string endpoint: ""
    property string operation: "install"
    property bool removeAfterStop: false
    property bool restartAfterStop: false
    // Asked to stop and not yet gone, so neither starting nor ready.
    property bool stopping: false
    // From the click, not from when the process has started, which is later.
    property bool launching: false
    readonly property bool installing: worker.running || launching
    readonly property bool checking: status.running
    readonly property bool serving: server.running
    readonly property int serverPid: server.processId ?? 0
    readonly property string helper: Qt.resolvedUrl("../assets/ai/runtime.py").toString().replace("file://", "")
    readonly property string log: info.destination ? info.destination + "/install.log" : ""
    // Why an installation cannot start now, in words; "" when it can. Download
    // is disabled exactly when this is set, and shows it.
    readonly property string installBlocker: {
        if (installing)
            return qsTr("Already installing");
        if (info.installed)
            return qsTr("Already installed");
        if (!info.destination)
            return checking ? qsTr("Checking this computer...") : error || qsTr("Could not check this computer. Press Refresh.");
        if ((info.missing ?? []).length > 0)
            return qsTr("Install these first: %1").arg(info.missing.join(", "));
        if ((info.freeBytes ?? 0) < (info.requiredBytes ?? 0))
            return qsTr("Needs %1 GiB free for the model and its build, %2 GiB free in %3").arg(gib(info.requiredBytes)).arg(gib(info.freeBytes)).arg(info.destination);
        return "";
    }

    signal ready

    function gib(bytes: real): string {
        return ((bytes ?? 0) / 1073741824).toFixed(1);
    }
    function stageLabel(name: string): string {
        return {
            starting: qsTr("Starting the installer"),
            waiting: qsTr("Waiting for the local model to stop"),
            source: qsTr("Fetching the pinned BitNet source"),
            build: qsTr("Building the CPU inference runtime"),
            download: qsTr("Downloading the model"),
            verify: qsTr("Checking that the model starts"),
            cancelling: qsTr("Cancelling")
        }[name] ?? name;
    }
    function refresh(): void {
        status.running = true;
    }
    function install(): void {
        if (installing)
            return;
        // Said, not silently ignored: the button that called this is visible.
        if (server.running) {
            stage = "";
            outcome = "failed";
            error = qsTr("Stop the local model before installing it again");
            return;
        }
        error = "";
        outcome = "";
        bytes = 0;
        total = 0;
        stageSince = lastEvent = now = Date.now();
        stage = "starting";
        message = stageLabel(stage);
        operation = "install";
        launching = true;
        // Left over from the last run, it would hide a failure to start.
        worker.didExit = false;
        worker.running = true;
    }
    function cancel(): void {
        if (!installing)
            return;
        stage = "cancelling";
        message = stageLabel(stage);
        // Not started yet: it is signalled the moment it is.
        if (worker.running)
            worker.signal(15);
    }
    function start(): void {
        idle.stop();
        if (endpoint) {
            ready();
            return;
        }
        if (server.running)
            return;
        error = "";
        server.running = true;
    }
    function release(): void {
        if (server.running)
            idle.restart();
    }
    function stop(): void {
        restartAfterStop = false;
        idle.stop();
        endpoint = "";
        if (server.running) {
            stopping = true;
            server.signal(15);
        }
    }
    // Stops the running server and starts it again once it has exited, as
    // uninstall() waits for it before removing.
    function restart(): void {
        if (installing || !server.running || stopping)
            return;
        stop();
        restartAfterStop = true;
    }
    function uninstall(): void {
        restartAfterStop = false;
        if (installing)
            return;
        if (server.running) {
            removeAfterStop = true;
            stop();
            return;
        }
        error = "";
        outcome = "";
        operation = "uninstall";
        worker.didExit = false;
        worker.running = true;
    }
    function event(line: string): void {
        try {
            const data = JSON.parse(line);
            lastEvent = Date.now();
            if (data.error)
                error = data.error;
            if (data.stage === "error" || data.stage === "cancelled" || data.stage === "installed") {
                // How it ended. installed is only ever reported once the
                // model has started and been moved into place.
                if (operation === "install" && outcome !== "installed")
                    outcome = data.stage === "error" ? "failed" : data.stage;
                message = outcome === "installed" ? qsTr("Installed") : outcome === "cancelled" ? qsTr("Installation cancelled") : "";
            } else if (data.stage === "removed") {
                message = qsTr("Removed");
            } else if (data.stage) {
                if (data.stage !== stage)
                    stageSince = lastEvent;
                stage = data.stage;
                message = stageLabel(stage);
                if (stage === "download") {
                    bytes = data.bytes ?? 0;
                    total = data.total ?? 0;
                }
            }
            // Availability, never preference. Discovering that the local
            // model is installed says nothing about whether the user chose it,
            // and refresh() runs on every startup, so writing the preference
            // here silently overwrote whatever they had selected. A managed
            // backend that is selected but not installed is caught where it
            // matters, at submit time.
            if (data.stage === "installed" || data.stage === "removed")
                info = data;
        } catch (e) {
            error = qsTr("Invalid installer response");
        }
    }

    Component.onCompleted: refresh()
    Component.onDestruction: {
        if (worker.running)
            worker.signal(15);
        if (server.running)
            server.signal(15);
    }

    // Only while installing: the elapsed time is what shows a long build has
    // not stopped.
    Timer {
        interval: 1000
        repeat: true
        running: worker.running
        onTriggered: root.now = Date.now()
    }
    Timer {
        id: idle

        interval: 300000
        onTriggered: root.stop()
    }
    Process {
        id: status

        property bool didExit: false

        command: ["uv", "run", "--no-project", "--python", "3.13", root.helper, "status"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.info = JSON.parse(text);
                } catch (e) {
                    root.error = qsTr("Unable to check local AI. Install uv first.");
                }
            }
        }
        onRunningChanged: {
            if (running)
                didExit = false;
            else
                Qt.callLater(() => {
                    if (!status.didExit)
                        root.error = qsTr("Could not check local AI. Install uv first.");
                });
        }
        onExited: { // qmllint disable signal-handler-parameters
            didExit = true;
        }
    }
    Process {
        id: worker

        property bool didExit: false

        command: ["uv", "run", "--no-project", "--python", "3.13", root.helper, root.operation]
        stdout: SplitParser {
            onRead: data => root.event(data)
        }
        onRunningChanged: {
            root.launching = false;
            if (running) {
                didExit = false;
                if (root.stage === "cancelling")
                    signal(15);
            } else {
                Qt.callLater(() => {
                    if (!worker.didExit) {
                        root.error = qsTr("Could not start the installer. Install uv first.");
                        if (root.operation === "install")
                            root.outcome = "failed";
                    }
                });
            }
        }
        onExited: code => { // qmllint disable signal-handler-parameters
            didExit = true;
            // The exit decides what an install that did not report its end
            // came to, so it never stays looking busy or successful.
            if (root.operation === "install" && root.outcome !== "installed") {
                if (code === 130 || root.outcome === "cancelled" || root.stage === "cancelling") {
                    root.outcome = "cancelled";
                    root.message = qsTr("Installation cancelled");
                } else {
                    root.outcome = "failed";
                    if (!root.error)
                        root.error = code === 0 ? qsTr("The installer ended without finishing") : qsTr("The installer stopped with exit code %1").arg(code);
                }
            } else if (code !== 0 && code !== 130 && !root.error) {
                root.error = qsTr("Could not remove the local model (exit code %1)").arg(code);
            }
            root.refresh();
        }
    }
    Process {
        id: server

        property bool didExit: false

        command: ["uv", "run", "--no-project", "--python", "3.13", root.helper, "serve", "--owner", String(Quickshell.processId)]
        stdout: SplitParser {
            onRead: line => {
                try {
                    const data = JSON.parse(line);
                    if (data.stage === "ready" && !root.stopping) {
                        root.endpoint = data.endpoint;
                        root.ready();
                        root.release();
                    }
                    if (data.error)
                        root.error = data.error;
                } catch (e) {
                    root.error = qsTr("Invalid local server response");
                }
            }
        }
        onRunningChanged: {
            if (running) {
                didExit = false;
            } else {
                root.stopping = false;
                Qt.callLater(() => {
                    if (!server.didExit)
                        root.error = qsTr("Could not start local AI. Install uv first.");
                });
            }
        }
        onExited: code => { // qmllint disable signal-handler-parameters
            didExit = true;
            root.endpoint = "";
            if (code !== 0 && code !== 130 && !root.error)
                root.error = qsTr("Local AI server stopped unexpectedly");
            if (root.removeAfterStop) {
                root.removeAfterStop = false;
                root.uninstall();
            } else if (root.restartAfterStop) {
                // After running has settled to false, or start() sees it still running.
                Qt.callLater(() => {
                    if (root.restartAfterStop) {
                        root.restartAfterStop = false;
                        root.start();
                    }
                });
            }
        }
    }
}
