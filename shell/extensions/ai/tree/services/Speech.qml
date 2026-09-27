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
    property string operation: "install"
    readonly property bool working: worker.running
    readonly property string helper: Qt.resolvedUrl("../assets/dictation/speech.py").toString().replace("file://", "")

    function refresh(): void {
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
            }
        } catch (e) {
            error = qsTr("Invalid speech helper response");
        }
    }

    Component.onCompleted: refresh()

    Process {
        id: status

        command: ["uv", "run", "--no-project", "--python", "3.13", root.helper, "status"]
        stdout: SplitParser {
            onRead: data => root.event(data)
        }
    }
    Process {
        id: worker

        command: ["uv", "run", "--no-project", "--python", "3.13", root.helper, root.operation]
        stdout: SplitParser {
            onRead: data => root.event(data)
        }
        onExited: code => { // qmllint disable signal-handler-parameters
            if (code !== 0 && code !== 130 && !root.error)
                root.error = qsTr("Could not %1 the speech model").arg(root.operation);
        }
    }
}
