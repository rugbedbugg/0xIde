pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config

// Reading text out of a captured region, in two shapes.
//
//   extract()  plain text straight to the clipboard. This is what the text
//              extraction keybind uses: tesseract, wl-copy, nothing else.
//   scan()     word positions as well as text, for the result window's table
//              reconstruction. Needs a helper, so it is not on the fast path.
Scope {
    id: root

    // Installed Tesseract languages. "osd" is orientation and script detection
    // rather than a recognition model, so it is not one.
    property var languages: []

    // Configured languages win when set; otherwise every installed one, which
    // is what Illogical Impulse does. "eng" is only the last resort for when
    // the listing failed.
    readonly property string effectiveLanguages: GlobalConfig.ai.ocrLanguages.trim() || languages.join("+") || "eng"

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

    Component.onCompleted: refreshLanguages()

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

    // --- extract: region -> tesseract -> clipboard ---------------------------

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
            copy.pending = text;
            copy.running = true;
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

    // --- scan: region -> word positions -> result window ---------------------

    property var result: ({})
    property string error: ""
    property string scanPath: ""
    property var resultScreen: null
    readonly property bool busy: recognition.running
    readonly property string helper: Qt.resolvedUrl("../assets/ocr/recognize.py").toString().replace("file://", "")
    // recognize.py is stdlib-only, so the distribution interpreter runs it.
    // Going through a version manager would add a dependency and pin a release
    // that need not be installed.
    readonly property string python: "/usr/bin/python3"

    signal recognized

    function scan(path: string, screen: var): void {
        if (recognition.running) {
            cleanup(path);
            error = qsTr("OCR is still processing the previous capture. Try again when it finishes.");
            return;
        }
        scanPath = path;
        resultScreen = screen;
        error = "";
        recognition.running = true;
    }

    Component.onDestruction: {
        recognition.running = false;
        extraction.running = false;
        cleanup(scanPath);
        cleanup(extractPath);
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
                    } else {
                        root.result = data;
                        root.recognized();
                    }
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
