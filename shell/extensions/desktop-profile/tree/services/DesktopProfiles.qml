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

    function refresh(): void {
        list.running = true;
    }

    // Detached: a switch outlives this call, and the shell stays responsive while it runs.
    function activate(id: string): void {
        if (id && id !== active?.id)
            Quickshell.execDetached([cli, "profile", "set", id]);
    }

    Component.onCompleted: refresh()

    Process {
        id: list

        command: [root.cli, "profile", "list", "--tsv"]
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
