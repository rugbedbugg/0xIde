pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config

// Reading text out of a captured region. Two entry points, deliberately:
//
//   capture()          the ordinary extractor. tesseract, wl-copy, delete the
//                      capture, done. It reports nothing, so nothing downstream
//                      can decide to open a window on the back of it.
//   captureForPanel()  the explicit AI-assisted call. Same clipboard result,
//                      but it also emits recognized() so the caller can open
//                      the result panel, and it collects word positions when
//                      the table view is switched on.
Scope {
    id: root

    // Installed Tesseract languages. "osd" is orientation and script detection
    // rather than a recognition model, so it is not one.
    property var languages: []
    // Tesseract itself could not be run, as opposed to having no language data.
    property bool engineMissing: false
    property var resultScreen: null
    property string error: ""
    // Reading or copying a capture right now.
    readonly property bool busy: extraction.running || recognition.running || copy.running

    // Configured languages win when set; otherwise every installed one, which
    // is what Illogical Impulse does. "eng" is only the last resort for when
    // the listing failed.
    readonly property string effectiveLanguages: GlobalConfig.ai.ocrLanguages.trim() || languages.join("+") || "eng"
    // Configured languages Tesseract has no data for.
    readonly property var missingLanguages: engineMissing || !languages.length ? [] : GlobalConfig.ai.ocrLanguages.trim().split("+").map(l => l.trim()).filter(l => l && !languages.includes(l))
    // Why text cannot be read right now, or "" when it can. The engine missing
    // and its language data missing are different problems, said differently.
    readonly property string readiness: {
        if (engineMissing)
            return qsTr("OCR requires Tesseract. Install tesseract first.");
        if (!languages.length)
            return qsTr("Tesseract has no language data. Install one, e.g. tesseract-data-eng.");
        if (missingLanguages.length)
            return missingLanguageText(missingLanguages);
        return "";
    }

    function missingLanguageText(codes: var): string {
        return qsTr("Tesseract has no data for %1. Install it (e.g. tesseract-data-%2) or change the OCR languages.").arg(codes.join(", ")).arg(codes[0]);
    }
    // Tesseract's own words for a language it could not load, as the reason.
    function explain(stderr: string, code: int): string {
        if (code === 127)
            return qsTr("OCR requires Tesseract. Install tesseract first.");
        // QML's JavaScript has no matchAll.
        const failed = unloaded(stderr);
        if (failed.length)
            return missingLanguageText(failed);
        return stderr.trim().split("\n").pop() || qsTr("Tesseract could not read the selected region.");
    }
    // Languages Tesseract said it could not load. With others it could, it
    // still reads, in those alone.
    function unloaded(stderr: string): var {
        // QML's JavaScript has no matchAll.
        const failed = [];
        const pattern = /Failed loading language '([^']+)'/g;
        for (let m = pattern.exec(stderr); m; m = pattern.exec(stderr))
            failed.push(m[1]);
        return failed;
    }
    // Read, but without some of the configured languages: said, not hidden.
    function warnPartial(codes: var): void {
        if (codes.length)
            notify(qsTr("Text read without %1").arg(codes.join(", ")), missingLanguageText(codes), false);
    }

    // Only fires for captureForPanel(), and only when there is something to
    // show. The ordinary extractor never emits it.
    signal recognized(string text, var structured)

    // The ordinary extractor. Always the short path: the table view belongs to
    // the panel, and the panel is not part of this flow.
    function capture(path: string): void {
        error = "";
        report = false;
        extract(path);
    }

    // The explicit AI-assisted call.
    function captureForPanel(path: string, screen: var): void {
        resultScreen = screen;
        error = "";
        report = true;
        if (GlobalConfig.ai.tableMode)
            scan(path);
        else
            extract(path);
    }

    // Whether the capture in flight should be reported to a caller.
    property bool report: false

    // didExit is reset here: a launch that never starts reports no exit, and
    // the last run's would hide that Tesseract has gone.
    function refreshLanguages(): void {
        if (listing.running)
            return;
        listing.didExit = false;
        listing.running = true;
    }

    // Only ever removes a capture this shell made for this purpose.
    function cleanup(path: string): void {
        if (path.startsWith("/tmp/caelestia-picker-" + Quickshell.processId + "-"))
            CUtils.deleteFile(Qt.resolvedUrl(path));
    }

    // As the shell's own notifications read: a symbolic icon, which the
    // notification view tints with the scheme, and urgency for the colour. A
    // failure is critical (error colours); nothing found or still busy is low.
    function notify(title: string, body: string, critical: bool): void {
        Quickshell.execDetached(["notify-send", "-a", "0xide", "-i", "edit-copy-symbolic", "-u", critical ? "critical" : "low", title, body]);
    }

    function publish(text: string, structured: var): void {
        copy.pending = text;
        copy.running = true;
        if (report)
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

        property bool didExit: false

        command: ["tesseract", "--list-langs"]
        stdout: StdioCollector {
            // The first line is a header, not a language.
            onStreamFinished: root.languages = text.split("\n").slice(1).map(line => line.trim()).filter(line => line && line !== "osd")
        }
        onRunningChanged: {
            if (running) {
                didExit = false;
                return;
            }
            // A command that cannot be started never reports an exit code.
            Qt.callLater(() => {
                if (!listing.didExit) {
                    root.engineMissing = true;
                    root.languages = [];
                }
            });
        }
        onExited: code => {
            didExit = true;
            root.engineMissing = false;
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

        // Read a grey copy three times the size: screen text is far below the
        // resolution Tesseract is trained on. Without magick, the capture as is.
        // Exit 127 when Tesseract itself is missing, whatever magick did.
        command: ["sh", "-c", 'command -v tesseract >/dev/null 2>&1 || exit 127; if command -v magick >/dev/null 2>&1; then magick "$1" -colorspace Gray -resize 300% png:- | tesseract stdin - -l "$2"; else tesseract "$1" - -l "$2"; fi', "sh", root.extractPath, root.effectiveLanguages]
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
                    root.settleExtraction(qsTr("The text extractor could not be started."), true);
            });
        }
        onExited: code => {
            exited = true;
            // Whatever happened, the settings show what is installed now.
            root.refreshLanguages();
            if (code !== 0) {
                root.settleExtraction(root.explain(extractionError.text, code), true);
                return;
            }
            const text = extracted.text.trim();
            if (!text) {
                root.settleExtraction(qsTr("Nothing was recognised in the selected region."), false);
                return;
            }
            root.settleExtraction("", false);
            root.warnPartial(root.unloaded(extractionError.text));
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

    // Word positions, for the table view. Only ever reached from
    // captureForPanel(), so the ordinary extractor never runs Python.
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
                    root.warnPartial(data.missing ?? []);
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
