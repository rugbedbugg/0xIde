pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The keyboard shortcuts overlay's data: the keybinds Hyprland has
// registered right now, read once each time the overlay opens, and searched
// here without asking Hyprland again. Nothing runs while it is closed, and the
// list is dropped on close rather than kept.
Singleton {
    id: root

    // assets/shortcuts/keybinds.py does the reading and wording; see there.
    property string helper: Quickshell.shellPath("assets/shortcuts/keybinds.py")

    property bool open
    // What the overlay shows: "closed", "loading" until this open's snapshot
    // has answered, then "ready", "empty" (Hyprland answered, and has no
    // binds) or "error". Only a snapshot that was read and parsed can make it
    // empty; a failure of any kind is an error instead.
    property string phase: "closed"
    readonly property bool loading: phase === "loading"
    property string error
    // Each bind as keybinds.py gives it, grouped and in a stable order.
    property var binds: []
    // False when the session's Lua binds carry no descriptions at all, so
    // what they do cannot be shown.
    property bool annotated: true
    property string query
    // How many times Hyprland has been asked, for the tests.
    property int snapshots
    // The snapshot whose answer counts. Each has its own reader, so one
    // still finishing from an earlier open or refresh can never land.
    property int request
    property var reader: null

    // Rows for the list: a header before each group's first bind. Every word
    // of the search has to appear in a bind's keys, description, action or
    // group, so "volume up" and "super w" both narrow it down.
    readonly property var rows: {
        const terms = query.toLowerCase().split(/\s+/).filter(t => t);
        const out = [];
        let group = null;
        for (const bind of binds) {
            if (!terms.every(t => bind.search.includes(t)))
                continue;
            if (bind.group !== group) {
                group = bind.group;
                out.push({ header: group });
            }
            out.push(bind);
        }
        return out;
    }
    readonly property int matches: rows.filter(r => !r.header).length

    function show(): void {
        query = "";
        // Loading before the window exists, so it is never built empty.
        phase = "loading";
        open = true;
        refresh();
    }

    function hide(): void {
        open = false;
        phase = "closed";
        stop();
        binds = [];
        error = "";
        query = "";
    }

    function toggle(): void {
        if (open)
            hide();
        else
            show();
    }

    // A fresh snapshot; only while open.
    function refresh(): void {
        if (!open)
            return;
        stop();
        phase = "loading";
        error = "";
        snapshots++;
        reader = readerComponent.createObject(root, {
            request: ++request
        });
    }

    // The current reader is stopped and forgotten; its answer, if any, is
    // for a request that no longer counts.
    function stop(): void {
        if (reader)
            reader.running = false;
        reader = null;
        request++;
    }

    function answer(from: int, text: string): void {
        if (from !== request || phase !== "loading")
            return;
        let data;
        try {
            data = JSON.parse(text);
        } catch (e) {
            fail(qsTr("The keybind list could not be read"));
            return;
        }
        if (!data || typeof data !== "object")
            fail(qsTr("The keybind list could not be read"));
        else if (data.error)
            fail(String(data.error));
        else if (!Array.isArray(data.binds))
            fail(qsTr("The keybind list was not in the expected form"));
        else {
            binds = data.binds;
            annotated = data.annotated !== false;
            error = "";
            phase = binds.length > 0 ? "ready" : "empty";
        }
    }

    function fail(reason: string): void {
        binds = [];
        error = reason;
        phase = "error";
    }

    Component {
        id: readerComponent

        Process {
            id: proc

            required property int request
            property bool didExit

            command: ["/usr/bin/python3", root.helper]
            running: true
            stdout: StdioCollector {
                onStreamFinished: root.answer(proc.request, text)
            }
            // A reader that cannot start reports no exit; one that exits
            // without having answered failed. Either way it is then gone.
            onExited: code => { // qmllint disable signal-handler-parameters
                didExit = true;
                if (code !== 0 && proc.request === root.request && root.phase === "loading")
                    root.fail(qsTr("The keybind reader stopped with exit code %1").arg(code));
            }
            onRunningChanged: {
                if (running)
                    return;
                Qt.callLater(() => {
                    if (!proc.didExit && proc.request === root.request && root.phase === "loading")
                        root.fail(qsTr("Could not start /usr/bin/python3"));
                    else if (proc.request === root.request && root.phase === "loading")
                        root.fail(qsTr("The keybind reader ended without an answer"));
                    if (root.reader === proc)
                        root.reader = null;
                    proc.destroy();
                });
            }
        }
    }
}
