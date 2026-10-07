pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// 0xIde's desktop profiles, as its command line lists them. The launcher's
// >theme and the Theme settings page both read this; neither knows which
// profiles exist, and switching is entirely the command line's job.
Singleton {
    id: root

    readonly property string cli: "@OXIDE_ROOT@/0xide"
    // [{ id, name, active, description }]
    property var profiles: []
    readonly property var active: profiles.find(p => p.active) ?? null
    // The profile a switch started from here is going to, until it ends.
    property string switchingTo: ""
    readonly property bool switching: switcher.running || switchingTo !== ""
    // Why the last switch, or the profile list, failed; "" when neither did.
    property string error: ""

    function refresh(): void {
        if (list.running)
            return;
        list.didExit = false;
        list.running = true;
    }

    // The command line does the switch and keeps the profile state. It runs in
    // its own session (setsid --wait), so it carries on even if this shell goes
    // away; while this shell stays, its exit refreshes the list and says why a
    // switch did not happen.
    function activate(id: string): void {
        if (!id || id === active?.id)
            return;
        if (switching) {
            error = qsTr("A desktop switch is already running");
            return;
        }
        error = "";
        switchingTo = id;
        switcher.didExit = false;
        switcher.command = ["setsid", "--wait", cli, "profile", "set", id];
        switcher.running = true;
    }
    function name(id: string): string {
        return profiles.find(p => p.id === id)?.name ?? id;
    }
    // The command line's own reason: its fail: line, or the step it failed at.
    function reason(stderr: string, code: int): string {
        const lines = stderr.split("\n").map(l => l.trim()).filter(l => l);
        const fail = lines.filter(l => l.startsWith("fail:")).pop();
        if (fail)
            return fail.slice(5).trim();
        const step = lines.filter(l => / failed at /.test(l)).pop();
        const restored = code === 2 ? qsTr("; the previous desktop could not be fully restored") : "";
        return (step || qsTr("The switch exited with code %1").arg(code)) + restored;
    }

    Component.onCompleted: refresh()

    Process {
        id: switcher

        property bool didExit: false

        stderr: StdioCollector {
            id: switchErrors
        }
        onRunningChanged: {
            if (!running)
                Qt.callLater(() => {
                    if (!switcher.didExit && root.switchingTo) {
                        root.error = qsTr("Could not start the desktop switch");
                        root.switchingTo = "";
                    }
                });
        }
        onExited: code => { // qmllint disable signal-handler-parameters
            didExit = true;
            if (code !== 0)
                root.error = root.reason(switchErrors.text, code);
            root.switchingTo = "";
            // Whatever happened, the list says what is active now.
            root.refresh();
        }
    }

    Process {
        id: list

        property bool didExit: false

        command: [root.cli, "profile", "list", "--tsv"]
        stderr: StdioCollector {
            id: listErrors
        }
        onRunningChanged: {
            if (!running)
                Qt.callLater(() => {
                    if (!list.didExit)
                        root.error = qsTr("Could not read the desktop profiles: %1 did not start").arg(root.cli);
                });
        }
        onExited: code => { // qmllint disable signal-handler-parameters
            didExit = true;
            if (code !== 0)
                root.error = qsTr("Could not read the desktop profiles: %1").arg(listErrors.text.trim() || qsTr("exit code %1").arg(code));
        }
        stdout: StdioCollector {
            onStreamFinished: root.profiles = text.split("\n").filter(line => line).map(line => {
                const [id, name, active, description] = line.split("\t");
                return {
                    id,
                    name,
                    active: active === "1",
                    description: description ?? ""
                };
            })
        }
    }
}
