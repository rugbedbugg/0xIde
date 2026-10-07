pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

// The info overlay on a wallpaper preview: which preview has it open, that
// image's pixel size, and moving it to the Trash. One overlay is open at a
// time, in the launcher and the settings page alike, so opening another
// closes the first.
Singleton {
    id: root

    readonly property string helper: Quickshell.shellPath("assets/wallpaper/imageinfo.py")

    // The path whose overlay is open; empty when none is.
    property string openPath
    // Pixel size of openPath, read from its header; 0 until known.
    property int width
    property int height
    property string error
    property bool trashing
    property string trashError

    function show(path: string): void {
        openPath = path;
        width = 0;
        height = 0;
        error = "";
        trashError = "";
        info.running = false;
        Qt.callLater(() => info.running = true);
    }

    function hide(): void {
        openPath = "";
    }

    function toggle(path: string): void {
        if (openPath === path)
            hide();
        else
            show(path);
    }

    // Moves the open image to the Trash. The wallpaper list watches its
    // folder, so the image leaves both pickers once it is gone.
    function trash(): void {
        if (!openPath || trashing)
            return;
        trashing = true;
        trashError = "";
        trashProc.target = openPath;
        trashProc.didExit = false;
        trashProc.running = true;
    }

    // gio's message without what the overlay already shows: its own name, the
    // file's URI and path. "gio: file:///…: Error trashing file …: No such
    // file or directory" is "No such file or directory"; gio also says
    // "Unable to trash file …: Permission denied".
    function trashReason(stderr: string, path: string): string {
        let text = stderr.trim().split("\n").pop() ?? "";
        text = text.replace(/^gio: file:\/\/\S+: /, "");
        for (const lead of [`Error trashing file ${path}: `, `Unable to trash file ${path}: `])
            if (text.startsWith(lead))
                text = text.slice(lead.length);
        return text || qsTr("Could not move it to the Trash");
    }

    // "2.4 MB", "980 KB": binary units, as the memory figure is.
    function formatBytes(bytes: real): string {
        if (bytes < 0)
            return "";
        if (bytes >= 1024 * 1024 * 1024)
            return qsTr("%1 GB").arg((bytes / 1024 / 1024 / 1024).toFixed(1));
        if (bytes >= 1024 * 1024)
            return qsTr("%1 MB").arg((bytes / 1024 / 1024).toFixed(bytes >= 100 * 1024 * 1024 ? 0 : 1));
        return qsTr("%1 KB").arg(Math.max(1, Math.round(bytes / 1024)));
    }

    Process {
        id: info

        command: ["/usr/bin/python3", root.helper, root.openPath]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    // A late answer for an overlay that has since moved on.
                    if (data.path !== root.openPath)
                        return;
                    if (data.error) {
                        root.error = data.error;
                    } else {
                        root.width = data.width;
                        root.height = data.height;
                    }
                } catch (e) {
                    root.error = qsTr("Could not read the image size");
                }
            }
        }
    }

    Process {
        id: trashProc

        property string target

        property bool didExit: false

        command: ["gio", "trash", "--", target]
        stderr: StdioCollector {
            id: trashStderr
        }
        // A command that cannot be started never reports an exit; without
        // this the button would stay on "Moving…".
        onRunningChanged: {
            if (!running)
                Qt.callLater(() => {
                    if (!trashProc.didExit && root.trashing) {
                        root.trashing = false;
                        root.trashError = qsTr("gio is not installed, so nothing was moved to the Trash");
                    }
                });
        }
        onExited: code => { // qmllint disable signal-handler-parameters
            didExit = true;
            root.trashing = false;
            if (code === 0) {
                if (root.openPath === target)
                    root.hide();
            } else {
                root.trashError = root.trashReason(trashStderr.text, target);
            }
        }
    }
}
