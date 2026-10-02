pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

Scope {
    id: root

    property var info: ({})
    property string message: ""
    property string error: ""
    property string endpoint: ""
    property string operation: "install"
    property bool removeAfterStop: false
    property bool restartAfterStop: false
    // Asked to stop and not yet gone, so neither starting nor ready.
    property bool stopping: false
    readonly property bool installing: worker.running
    readonly property bool serving: server.running
    readonly property int serverPid: server.processId ?? 0
    readonly property string helper: Qt.resolvedUrl("../assets/ai/runtime.py").toString().replace("file://", "")

    signal ready

    function refresh(): void {
        status.running = true;
    }
    function install(): void {
        if (worker.running || server.running)
            return;
        error = "";
        operation = "install";
        worker.running = true;
    }
    function cancel(): void {
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
        if (worker.running || !server.running || stopping)
            return;
        stop();
        restartAfterStop = true;
    }
    function uninstall(): void {
        restartAfterStop = false;
        if (worker.running)
            return;
        if (server.running) {
            removeAfterStop = true;
            stop();
            return;
        }
        operation = "uninstall";
        worker.running = true;
    }
    function event(line: string): void {
        try {
            const data = JSON.parse(line);
            if (data.error)
                error = data.error;
            message = data.message ?? data.stage ?? "";
            if (data.stage === "download")
                message = qsTr("Downloading model: %1 / %2 MiB").arg(Math.round(data.bytes / 1048576)).arg(Math.round(data.total / 1048576));
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
            if (running)
                didExit = false;
            else
                Qt.callLater(() => {
                    if (!worker.didExit)
                        root.error = qsTr("Could not start the installer. Install uv first.");
                });
        }
        onExited: code => { // qmllint disable signal-handler-parameters
            didExit = true;
            if (code !== 0 && code !== 130 && !root.error)
                root.error = qsTr("Installer failed. See the installation log in %1.").arg(root.info.destination ?? "caelestia/ai");
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
