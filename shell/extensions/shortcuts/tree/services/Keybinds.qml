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
    property bool loading
    property string error
    // Each bind as keybinds.py gives it, grouped and in a stable order.
    property var binds: []
    property string query
    // How many times Hyprland has been asked, for the tests.
    property int snapshots

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
        open = true;
        refresh();
    }

    function hide(): void {
        open = false;
        reader.running = false;
        loading = false;
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
        loading = true;
        error = "";
        reader.running = false;
        snapshots++;
        Qt.callLater(() => {
            if (root.open)
                reader.running = true;
        });
    }

    Process {
        id: reader

        command: ["/usr/bin/python3", root.helper]
        stdout: StdioCollector {
            onStreamFinished: {
                // A late answer for an overlay that has since closed.
                if (!root.open)
                    return;
                root.loading = false;
                try {
                    const data = JSON.parse(text);
                    if (data.error) {
                        root.error = data.error;
                        root.binds = [];
                    } else {
                        root.binds = Array.isArray(data.binds) ? data.binds : [];
                    }
                } catch (e) {
                    root.error = qsTr("The keybind list could not be read");
                    root.binds = [];
                }
            }
        }
        onExited: code => { // qmllint disable signal-handler-parameters
            if (root.open && root.loading && code !== 0) {
                root.loading = false;
                root.error = qsTr("The keybind list could not be read");
            }
        }
    }
}
