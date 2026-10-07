pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// The whisper.cpp model behind voice dictation, through assets/dictation/speech.py.
// Listening and typing is speech.py listen, turned on and off by
// assets/dictation/dictate.sh on its key.
Scope {
    id: root

    property var info: ({})
    property string message: ""
    property string error: ""
    // Why the last status check failed, kept apart from error so that a check
    // that later succeeds clears it.
    property string statusError: ""
    property string operation: "install"
    readonly property bool working: worker.running
    readonly property bool checking: status.running
    // Why the model cannot be downloaded right now, or "" when it can. The
    // install dialog shows it, so Download is never disabled without a reason.
    readonly property string installBlocker: {
        if (info.installed)
            return qsTr("Already installed");
        if (!info.destination)
            return checking ? qsTr("Checking this computer...") : statusError || qsTr("Could not check this computer.");
        if ((info.freeBytes ?? 0) <= (info.downloadBytes ?? 0))
            return qsTr("Needs %1 MiB free, %2 MiB free in %3").arg(Math.ceil(info.downloadBytes / 1048576)).arg(Math.floor(info.freeBytes / 1048576)).arg(info.destination);
        return "";
    }
    readonly property string helper: Qt.resolvedUrl("../assets/dictation/speech.py").toString().replace("file://", "")

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
    function run(action: string): void {
        if (worker.running)
            return;
        error = "";
        message = "";
        operation = action;
        worker.didExit = false;
        worker.running = true;
    }
    function event(line: string): void {
        try {
            const data = JSON.parse(line);
            if (data.error)
                error = data.error;
            if (data.stage === "download")
                message = qsTr("Downloading: %1 / %2 MiB").arg(Math.round(data.bytes / 1048576)).arg(Math.round(data.total / 1048576));
            if (data.installed !== undefined) {
                info = data;
                message = "";
                statusError = "";
            }
        } catch (e) {
            error = qsTr("Invalid speech helper response");
        }
    }

    Component.onCompleted: refresh()

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
            if (running)
                didExit = false;
            else
                Qt.callLater(() => {
                    if (!worker.didExit)
                        root.error = qsTr("Could not start the speech model installer. Install uv first.");
                });
        }
        onExited: code => { // qmllint disable signal-handler-parameters
            didExit = true;
            if (code !== 0 && code !== 130 && !root.error)
                root.error = qsTr("Could not %1 the speech model").arg(root.operation);
        }
    }
}
