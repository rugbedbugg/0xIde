pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// The whisper.cpp model behind voice dictation, through assets/dictation/speech.py.
// Listening and typing is speech.py listen, turned on and off by
// assets/dictation/dictate.sh on its key.
//
// Installing it reports the same way AiRuntime does (stage, outcome, bytes,
// times), so components/InstallProgress shows either.
Scope {
    id: root

    property var info: ({})
    property string message: ""
    property string error: ""
    // Why the last status check failed, kept apart from error so that a check
    // that later succeeds clears it.
    property string statusError: ""
    property string operation: "install"
    // The installer as it goes: the step it reported last (starting, download,
    // verify), how it ended (installed, failed, cancelled; "" while running or
    // before any), and times in ms.
    property string stage: ""
    property string outcome: ""
    property real bytes: 0
    property real total: 0
    property real stageSince: 0
    property real lastEvent: 0
    property real now: 0
    // From the click, not from when the process has started, which is later.
    property bool launching: false
    readonly property bool working: worker.running || launching
    readonly property bool installing: working && operation === "install"
    readonly property bool checking: status.running
    // The model is one file; there is no log beyond the error itself.
    readonly property string log: ""
    // Why the model cannot be downloaded right now, or "" when it can. The
    // install dialog shows it, so Download is never disabled without a reason.
    readonly property string installBlocker: {
        if (working)
            return qsTr("Already working");
        if (info.installed)
            return qsTr("Already installed");
        if (!info.destination)
            return checking ? qsTr("Checking this computer...") : statusError || qsTr("Could not check this computer.");
        if ((info.freeBytes ?? 0) <= (info.downloadBytes ?? 0))
            return qsTr("Needs %1 MiB free, %2 MiB free in %3").arg(Math.ceil(info.downloadBytes / 1048576)).arg(Math.floor(info.freeBytes / 1048576)).arg(info.destination);
        return "";
    }
    readonly property string helper: Qt.resolvedUrl("../assets/dictation/speech.py").toString().replace("file://", "")

    function stageLabel(name: string): string {
        return {
            starting: qsTr("Starting the download"),
            download: qsTr("Downloading the speech model"),
            verify: qsTr("Checking the model against its pinned hash"),
            cancelling: qsTr("Cancelling")
        }[name] ?? name;
    }
    // didExit is reset at each launch: one that never starts reports no exit,
    // and the last run's would hide that.
    function refresh(): void {
        if (status.running)
            return;
        status.didExit = false;
        status.running = true;
    }
    function install(): void {
        run("install");
    }
    function remove(): void {
        run("remove");
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
    function run(action: string): void {
        if (working)
            return;
        error = "";
        message = "";
        outcome = "";
        operation = action;
        bytes = 0;
        total = 0;
        stageSince = lastEvent = now = Date.now();
        stage = action === "install" ? "starting" : "";
        if (stage)
            message = stageLabel(stage);
        launching = true;
        worker.didExit = false;
        worker.running = true;
    }
    function event(line: string): void {
        try {
            const data = JSON.parse(line);
            lastEvent = Date.now();
            if (data.error)
                error = data.error;
            if (operation === "install" && (data.stage === "error" || data.stage === "cancelled" || data.stage === "installed")) {
                if (outcome !== "installed")
                    outcome = data.stage === "error" ? "failed" : data.stage;
            } else if (operation === "install" && data.stage && data.stage !== "status") {
                if (data.stage !== stage)
                    stageSince = lastEvent;
                stage = data.stage;
                message = stageLabel(stage);
                if (stage === "download") {
                    bytes = data.bytes ?? 0;
                    total = data.total ?? 0;
                }
            }
            if (data.installed !== undefined) {
                info = data;
                if (data.stage !== "download")
                    message = "";
                statusError = "";
            }
        } catch (e) {
            error = qsTr("Invalid speech helper response");
        }
    }

    Component.onCompleted: refresh()

    // Only while working: the elapsed time is what shows a slow download has
    // not stopped.
    Timer {
        interval: 1000
        repeat: true
        running: worker.running
        onTriggered: root.now = Date.now()
    }
    Process {
        id: status

        property bool didExit: false

        command: ["uv", "run", "--no-project", "--python", "3.13", root.helper, "status"]
        stdout: SplitParser {
            onRead: data => root.event(data)
        }
        // A command that cannot be started never reports an exit.
        onRunningChanged: {
            if (running)
                didExit = false;
            else
                Qt.callLater(() => {
                    if (!status.didExit)
                        root.statusError = qsTr("Could not check dictation. Install uv first.");
                });
        }
        onExited: code => { // qmllint disable signal-handler-parameters
            didExit = true;
            if (code !== 0 && !root.info.destination)
                root.statusError = qsTr("Could not check dictation (exit code %1).").arg(code);
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
                        root.error = qsTr("Could not start the speech model installer. Install uv first.");
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
                    root.message = "";
                } else {
                    root.outcome = "failed";
                    if (!root.error)
                        root.error = code === 0 ? qsTr("The download ended without finishing") : qsTr("The speech model installer stopped with exit code %1").arg(code);
                }
            } else if (code !== 0 && code !== 130 && !root.error) {
                root.error = qsTr("Could not remove the speech model (exit code %1)").arg(code);
            }
            root.message = "";
            root.refresh();
        }
    }
}
