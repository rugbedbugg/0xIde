pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config

// Reading text out of a captured region. One entry point, capture(), which
// always puts the text on the clipboard and always reports it.
//
// Word positions cost a Python helper and are only used by the table view, so
// they are collected only when that view is switched on. Everything else takes
// the short path: tesseract, wl-copy, delete the capture.
Scope {
    id: root

    // Installed Tesseract languages. "osd" is orientation and script detection
    // rather than a recognition model, so it is not one.
    property var languages: []
    property var resultScreen: null
    property string error: ""

    // Configured languages win when set; otherwise every installed one, which
    // is what Illogical Impulse does. "eng" is only the last resort for when
    // the listing failed.
    readonly property string effectiveLanguages: GlobalConfig.ai.ocrLanguages.trim() || languages.join("+") || "eng"

    // Only fires when there is something to show.
    signal recognized(string text, var structured)

    function capture(path: string, screen: var): void {
        resultScreen = screen;
        error = "";
        if (GlobalConfig.ai.tableMode)
            scan(path);
        else
            extract(path);
    }

    function refreshLanguages(): void {
        listing.running = true;
    }

    // Only ever removes a capture this shell made for this purpose.
    function cleanup(path: string): void {
        if (path.startsWith("/tmp/caelestia-picker-" + Quickshell.processId + "-"))
            CUtils.deleteFile(Qt.resolvedUrl(path));
    }

    function notify(title: string, body: string, critical: bool): void {
        const args = ["notify-send", "-a", "caelestia"];
        if (critical)
            args.push("-u", "critical");
        Quickshell.execDetached(args.concat([title, body]));
    }

    function publish(text: string, structured: var): void {
        copy.pending = text;
        copy.running = true;
        root.recognized(text, structured);
    }

    Component.onCompleted: refreshLanguages()
    Component.onDestruction: {
        recognition.running = false;
        extraction.running = false;
        cleanup(scanPath);
        cleanup(extractPath);
    }

    Process {
        id: listing

        command: ["tesseract", "--list-langs"]
        stdout: StdioCollector {
            // The first line is a header, not a language.
            onStreamFinished: root.languages = text.split("\n").slice(1).map(line => line.trim()).filter(line => line && line !== "osd")
        }
        onExited: code => {
            if (code !== 0)
                root.languages = [];
        }
    }

    // --- short path: region -> tesseract -> clipboard ------------------------

    property string extractPath: ""

    function extract(path: string): void {
        if (extraction.running) {
            // One capture at a time. Dropping the new one is better than
            // leaving its file behind or racing the clipboard.
            cleanup(path);
            root.notify(qsTr("Still reading the last region"), qsTr("Try again once it finishes."), false);
            return;
        }
        extractPath = path;
        extraction.running = true;
    }

    // Finishes an extraction: removes the capture, then reports. extractPath
    // itself is left alone, because Process.command is bound to it and must not
    // change while the process is still settling; the next capture replaces it.
    function settleExtraction(message: string, critical: bool): void {
        cleanup(extractPath);
        if (message)
            root.notify(critical ? qsTr("Text extraction failed") : qsTr("No text found"), message, critical);
    }

    Process {
        id: extraction

        property bool exited: false

        command: ["tesseract", root.extractPath, "-", "-l", root.effectiveLanguages]
        stdout: StdioCollector {
            id: extracted
        }
        stderr: StdioCollector {
            id: extractionError
        }

        onRunningChanged: {
            if (running) {
                exited = false;
                return;
            }
            // A command that cannot be started never reports an exit code.
            Qt.callLater(() => {
                if (!extraction.exited)
                    root.settleExtraction(qsTr("tesseract is not installed."), true);
            });
        }
        onExited: code => {
            exited = true;
            if (code !== 0) {
                root.settleExtraction(extractionError.text.trim() || qsTr("Tesseract could not read the selected region."), true);
                return;
            }
            const text = extracted.text.trim();
            if (!text) {
                root.settleExtraction(qsTr("Nothing was recognised in the selected region."), false);
                return;
            }
            root.settleExtraction("", false);
            root.publish(text, ({}));
        }
    }

    Process {
        id: copy

        property string pending: ""
        property bool exited: false

        command: ["wl-copy", "-n", "--", pending]

        onRunningChanged: {
            if (running) {
                exited = false;
                return;
            }
            Qt.callLater(() => {
                if (!copy.exited)
                    root.notify(qsTr("Text extraction failed"), qsTr("wl-copy is not installed, so the text could not be copied."), true);
            });
        }
        onExited: code => {
            exited = true;
            if (code !== 0)
                root.notify(qsTr("Text extraction failed"), qsTr("wl-copy could not take the recognised text."), true);
        }
    }

    // --- structured path: also collects word positions, for the table view ---

    property string scanPath: ""
    readonly property string helper: Qt.resolvedUrl("../assets/ocr/recognize.py").toString().replace("file://", "")
    // recognize.py is stdlib-only, so the distribution interpreter runs it.
    // Going through a version manager would add a dependency and pin a release
    // that need not be installed.
    readonly property string python: "/usr/bin/python3"

    function scan(path: string): void {
        if (recognition.running) {
            cleanup(path);
            root.notify(qsTr("Still reading the last region"), qsTr("Try again once it finishes."), false);
            return;
        }
        scanPath = path;
        recognition.running = true;
    }

    Process {
        id: recognition

        property bool didExit: false

        command: [root.python, root.helper, root.scanPath, "--language", root.effectiveLanguages]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const data = JSON.parse(text);
                    if (data.error) {
                        root.error = data.error;
                        return;
                    }
                    const recognised = (data.text ?? "").trim();
                    if (!recognised) {
                        root.notify(qsTr("No text found"), qsTr("Nothing was recognised in the selected region."), false);
                        return;
                    }
                    root.publish(recognised, data);
                } catch (error) {
                    root.error = qsTr("OCR helper failed. Check the Tesseract installation.");
                }
            }
        }
        onRunningChanged: {
            if (running)
                didExit = false;
            else
                Qt.callLater(() => {
                    if (!recognition.didExit) {
                        root.error = qsTr("Could not start the OCR helper.");
                        root.cleanup(root.scanPath);
                    }
                });
        }
        onExited: code => { // qmllint disable signal-handler-parameters
            didExit = true;
            root.cleanup(root.scanPath);
            if (code !== 0 && !root.error)
                root.error = qsTr("OCR failed. Check the Tesseract installation.");
        }
    }
}
