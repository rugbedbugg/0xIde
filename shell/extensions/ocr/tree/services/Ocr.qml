pragma Singleton
pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Io
import Caelestia
import Caelestia.Config

Scope {
    id: root

    property var result: ({})
    property var languages: []
    property string error: ""
    property string imagePath: ""
    property string languageOverride: ""
    property var resultScreen: null
    readonly property bool busy: recognition.running
    readonly property string helper: Qt.resolvedUrl("../assets/ocr/recognize.py").toString().replace("file://", "")

    signal recognized

    function scan(path: string, screen: var, language: string): void {
        if (recognition.running) {
            cleanup(path);
            error = qsTr("OCR is still processing the previous capture. Try again when it finishes.");
            return;
        }
        languageOverride = language || GlobalConfig.ai.ocrLanguages;
        imagePath = path;
        resultScreen = screen;
        error = "";
        recognition.running = true;
    }

    function cleanup(path: string): void {
        if (path.startsWith("/tmp/caelestia-picker-" + Quickshell.processId + "-"))
            CUtils.deleteFile(Qt.resolvedUrl(path));
    }

    function refreshLanguages(): void {
        listing.running = true;
    }

    Component.onCompleted: refreshLanguages()
    Component.onDestruction: {
        recognition.running = false;
        cleanup(imagePath);
    }

    Process {
        id: recognition

        property bool didExit: false

        command: ["uv", "run", "--no-project", "--python", "3.13", root.helper, root.imagePath, "--language", root.languageOverride]
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
                    root.error = qsTr("OCR helper failed. Check uv and Tesseract installation.");
                }
            }
        }
        onRunningChanged: {
            if (running)
                didExit = false;
            else
                Qt.callLater(() => {
                    if (!recognition.didExit) {
                        root.error = qsTr("Could not start OCR. Install uv and Tesseract first.");
                        root.cleanup(root.imagePath);
                    }
                });
        }
        onExited: code => { // qmllint disable signal-handler-parameters
            didExit = true;
            root.cleanup(root.imagePath);
            if (code !== 0 && !root.error)
                root.error = qsTr("OCR failed. Check uv and Tesseract installation.");
        }
    }

    Process {
        id: listing

        command: ["uv", "run", "--no-project", "--python", "3.13", root.helper, "--languages"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.languages = JSON.parse(text).languages ?? [];
                } catch (error) {
                    root.languages = [];
                }
            }
        }
    }
}
