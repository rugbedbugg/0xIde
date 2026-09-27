pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io

// Offline translation languages and requests, through assets/ai/translate.py.
// Each installed language is a pair of Argos models through English, so any
// two installed languages translate into each other.
Scope {
    id: root

    property list<string> installed: []
    property var available: []
    property string message: ""
    property string error: ""
    property string operation: ""
    property string language: ""
    readonly property bool working: worker.running
    readonly property bool translating: translation.running
    readonly property string helper: Qt.resolvedUrl("../assets/ai/translate.py").toString().replace("file://", "")

    signal translated(string text)
    signal failed(string error)

    function refresh(): void {
        status.running = true;
    }
    function install(code: string): void {
        run("install", code);
    }
    function remove(code: string): void {
        run("remove", code);
    }
    function run(action: string, code: string): void {
        if (worker.running || !code)
            return;
        error = "";
        message = "";
        operation = action;
        language = code;
        worker.running = true;
    }
    function name(code: string): string {
        return available.find(l => l.code === code)?.name ?? code;
    }
    // Whether a translation needs nothing more than what is installed.
    function canTranslate(from: string, to: string): bool {
        return !!from && !!to && from !== to && installed.includes(from) && installed.includes(to);
    }
    function translate(text: string, from: string, to: string): void {
        if (translation.running)
            return;
        translation.command = ["uv", "run", "--no-project", "--python", "3.13", root.helper, "translate", from, to, text];
        translation.running = true;
    }
    function cancel(): void {
        if (translation.running)
            translation.signal(15);
    }
    function event(line: string): void {
        try {
            const data = JSON.parse(line);
            if (data.error)
                error = data.error;
            if (data.installed)
                installed = data.installed;
            if (data.available?.length)
                available = data.available;
            if (data.stage === "download")
                message = qsTr("Downloading %1: %2 / %3 MiB").arg(data.package).arg(Math.round(data.bytes / 1048576)).arg(Math.round(data.total / 1048576));
            else if (data.stage === "installed" || data.stage === "removed")
                message = "";
        } catch (e) {
            error = qsTr("Invalid translation helper response");
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

        command: ["uv", "run", "--no-project", "--python", "3.13", root.helper, root.operation, root.language]
        stdout: SplitParser {
            onRead: data => root.event(data)
        }
        onExited: code => { // qmllint disable signal-handler-parameters
            if (code !== 0 && code !== 130 && !root.error)
                root.error = qsTr("Could not %1 %2").arg(root.operation).arg(root.name(root.language));
            root.message = "";
        }
    }
    Process {
        id: translation

        // The exit and the end of each stream arrive in no fixed order, so the
        // result is reported once all three have.
        property int exitCode: -1
        property int streamsDone: 0

        function settle(): void {
            if (exitCode < 0 || streamsDone < 2)
                return;
            if (exitCode === 0)
                root.translated(output.text);
            else if (exitCode !== 143)
                root.failed(problems.text.trim().split("\n").pop() || qsTr("Translation failed"));
        }

        stdout: StdioCollector {
            id: output

            onStreamFinished: {
                translation.streamsDone++;
                translation.settle();
            }
        }
        stderr: StdioCollector {
            id: problems

            onStreamFinished: {
                translation.streamsDone++;
                translation.settle();
            }
        }
        onRunningChanged: if (running) {
            exitCode = -1;
            streamsDone = 0;
        }
        onExited: code => { // qmllint disable signal-handler-parameters
            exitCode = code;
            settle();
        }
    }
}
