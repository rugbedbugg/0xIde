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
    // Why the language list could not be read, kept apart from error so that
    // a later check that works clears it.
    property string statusError: ""
    property string operation: ""
    property string language: ""
    readonly property bool working: worker.running
    // From the call, not from when the process has started, which is later.
    readonly property bool translating: translation.running || translationStage !== ""
    // Where the translation in flight is: starting, preparing (the runtime
    // packages, downloaded the first time) or translating; "" when none is.
    property string translationStage: ""
    readonly property string translationLabel: ({
            starting: qsTr("Starting offline translation…"),
            preparing: qsTr("Preparing the offline translation runtime; the first time downloads it…"),
            translating: qsTr("Translating on this computer…")
        })[translationStage] ?? ""
    readonly property string helper: Qt.resolvedUrl("../assets/ai/translate.py").toString().replace("file://", "")

    signal translated(string text)
    signal failed(string error)

    // didExit is reset at each launch: one that never starts reports no exit,
    // and the last run's would hide that.
    function refresh(): void {
        if (status.running)
            return;
        status.didExit = false;
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
        if (translating)
            return;
        translation.command = ["uv", "run", "--no-project", "--python", "3.13", root.helper, "translate", from, to, text];
        translationStage = "starting";
        translation.problem = "";
        translation.didExit = false;
        translation.cancelPending = false;
        translation.running = true;
    }
    function cancel(): void {
        if (translation.running)
            translation.signal(15);
        else if (translationStage)
            // Not started yet: stopped the moment it is.
            translation.cancelPending = true;
    }
    function event(line: string): void {
        try {
            const data = JSON.parse(line);
            if (data.error)
                error = data.error;
            if (data.installed)
                installed = data.installed;
            if (data.available?.length) {
                available = data.available;
                statusError = "";
            }
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

        property bool didExit: false

        command: ["uv", "run", "--no-project", "--python", "3.13", root.helper, "status"]
        stdout: SplitParser {
            onRead: data => root.event(data)
        }
        // A command that cannot be started never reports an exit.
        onRunningChanged: {
            if (!running)
                Qt.callLater(() => {
                    if (!status.didExit)
                        root.statusError = qsTr("Could not load the language list. Install uv first.");
                });
        }
        onExited: { // qmllint disable signal-handler-parameters
            didExit = true;
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
        // The last line on stderr that is not a stage: the reason it failed.
        property string problem: ""
        property bool didExit: false
        property bool cancelPending: false

        function settle(): void {
            if (exitCode < 0 || streamsDone < 1)
                return;
            root.translationStage = "";
            if (exitCode === 0)
                root.translated(output.text);
            else if (exitCode !== 143 && !cancelPending)
                root.failed(problem || qsTr("Translation failed"));
        }

        stdout: StdioCollector {
            id: output

            onStreamFinished: {
                translation.streamsDone++;
                translation.settle();
            }
        }
        // Read as it comes, for the stages; QProcess delivers it all before
        // the exit, so the reason is in place when settle() runs.
        stderr: SplitParser {
            onRead: line => {
                try {
                    const data = JSON.parse(line);
                    if (data.stage) {
                        root.translationStage = data.stage;
                        return;
                    }
                } catch (e) {}
                if (line.trim())
                    translation.problem = line.trim();
            }
        }
        onRunningChanged: {
            if (running) {
                exitCode = -1;
                streamsDone = 0;
                if (cancelPending)
                    signal(15);
                return;
            }
            Qt.callLater(() => {
                if (!translation.didExit && root.translationStage) {
                    root.translationStage = "";
                    root.failed(qsTr("Could not start offline translation. Install uv first."));
                }
            });
        }
        onExited: code => { // qmllint disable signal-handler-parameters
            didExit = true;
            exitCode = code;
            settle();
        }
    }
}
