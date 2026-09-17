pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

ColumnLayout {
    id: root

    property bool confirmInstall: false
    property bool confirmRemove: false

    spacing: Tokens.spacing.medium

    Component.onDestruction: probe.cancel()

    StyledText {
        Layout.fillWidth: true
        text: qsTr("AI backend")
        font: Tokens.font.title.medium
    }
    ComboBox {
        Layout.fillWidth: true
        model: [qsTr("Not configured"), qsTr("Existing OpenAI-compatible server"), qsTr("Experimental local BitNet")]
        currentIndex: GlobalConfig.ai.backend === "managed" ? 2 : GlobalConfig.ai.backend === "external" ? 1 : 0
        onActivated: index => GlobalConfig.ai.backend = ["", "external", "managed"][index]
    }
    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: GlobalConfig.ai.backend === "external" ? qsTr("Text is sent to the URL below only when you submit an AI action.") : qsTr("BitNet runs on this computer. This experimental backend can produce repetitive or incorrect answers. The existing-server option lets you try another model.")
    }
    StyledTextField {
        Layout.fillWidth: true
        visible: GlobalConfig.ai.backend === "external"
        placeholderText: qsTr("Chat completions URL")
        text: GlobalConfig.ai.backendUrl
        onEditingFinished: GlobalConfig.ai.backendUrl = text.trim()
    }
    StyledTextField {
        Layout.fillWidth: true
        visible: GlobalConfig.ai.backend === "external"
        placeholderText: qsTr("Model name (optional)")
        text: GlobalConfig.ai.model
        onEditingFinished: GlobalConfig.ai.model = text.trim()
    }
    StyledTextField {
        Layout.fillWidth: true
        placeholderText: qsTr("System prompt (optional)")
        text: GlobalConfig.ai.systemPrompt
        onEditingFinished: GlobalConfig.ai.systemPrompt = text
    }
    TextButton {
        visible: GlobalConfig.ai.backend === "external"
        text: probe.running ? qsTr("Cancel test") : qsTr("Test connection")
        onClicked: {
            if (probe.running) {
                probe.cancel();
                return;
            }
            const payload = {
                messages: [
                    {
                        role: "user",
                        content: "Reply with OK."
                    }
                ],
                max_tokens: 8,
                stream: true
            };
            if (GlobalConfig.ai.model)
                payload.model = GlobalConfig.ai.model;
            probe.send(GlobalConfig.ai.backendUrl, JSON.stringify(payload));
        }
    }
    StyledText {
        Layout.fillWidth: true
        visible: !!probe.status
        wrapMode: Text.Wrap
        text: probe.error || (probe.status === "complete" ? qsTr("Connection succeeded") : probe.status)
    }
    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: qsTr("Local model: %1\nDisk usage: %2 MiB\nLocation: %3").arg(AiRuntime.info.installed ? qsTr("Installed") : qsTr("Not installed")).arg(Math.round((AiRuntime.info.diskBytes ?? 0) / 1048576)).arg(AiRuntime.info.destination ?? "")
    }
    RowLayout {
        TextButton {
            text: qsTr("Refresh status")
            onClicked: AiRuntime.refresh()
        }
        TextButton {
            visible: !AiRuntime.info.installed && !AiRuntime.installing
            text: qsTr("Install local model")
            onClicked: {
                AiRuntime.refresh();
                root.confirmInstall = true;
            }
        }
        TextButton {
            visible: AiRuntime.installing
            text: qsTr("Cancel installation")
            onClicked: AiRuntime.cancel()
        }
        TextButton {
            visible: !!AiRuntime.info.installed
            text: qsTr("Stop server")
            onClicked: AiRuntime.stop()
        }
        TextButton {
            visible: !!AiRuntime.info.installed
            text: qsTr("Uninstall")
            onClicked: root.confirmRemove = true
        }
    }
    StyledText {
        Layout.fillWidth: true
        visible: root.confirmInstall
        wrapMode: Text.Wrap
        text: qsTr("Download %1 MiB; requires %2 MiB free. Available: %3 MiB. Installs only under %4.\nMissing prerequisites: %5").arg(Math.round((AiRuntime.info.downloadBytes ?? 0) / 1048576)).arg(Math.round((AiRuntime.info.requiredBytes ?? 0) / 1048576)).arg(Math.round((AiRuntime.info.freeBytes ?? 0) / 1048576)).arg(AiRuntime.info.destination ?? "").arg((AiRuntime.info.missing ?? []).join(", ") || qsTr("None"))
    }
    RowLayout {
        visible: root.confirmInstall

        TextButton {
            text: qsTr("Download and install")
            enabled: !!AiRuntime.info.destination && !(AiRuntime.info.missing ?? []).length && AiRuntime.info.freeBytes >= AiRuntime.info.requiredBytes
            onClicked: {
                root.confirmInstall = false;
                AiRuntime.install();
            }
        }
        TextButton {
            text: qsTr("Cancel")
            onClicked: root.confirmInstall = false
        }
    }
    StyledText {
        Layout.fillWidth: true
        visible: root.confirmRemove
        wrapMode: Text.Wrap
        text: qsTr("Remove the managed model and its runtime? Your external servers and settings are kept.")
    }
    RowLayout {
        visible: root.confirmRemove

        TextButton {
            text: qsTr("Remove managed files")
            onClicked: {
                root.confirmRemove = false;
                AiRuntime.uninstall();
            }
        }
        TextButton {
            text: qsTr("Keep files")
            onClicked: root.confirmRemove = false
        }
    }
    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: AiRuntime.error || AiRuntime.message
    }
    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: qsTr("Manual setup: run an OpenAI-compatible server, select Existing server, and enter its chat completions URL and model name above. Managed installation requires uv, git, CMake, Ninja, clang and clang++. Install missing system prerequisites with your distribution's package manager, then retry.")
    }
    StyledText {
        text: qsTr("OCR languages")
        font: Tokens.font.title.medium
    }
    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: qsTr("Installed: %1").arg(Ocr.languages.join(", ") || qsTr("None found"))
    }
    StyledTextField {
        Layout.fillWidth: true
        placeholderText: qsTr("Tesseract languages, for example eng+deu. Empty uses all installed")
        text: GlobalConfig.ai.ocrLanguages
        onEditingFinished: GlobalConfig.ai.ocrLanguages = text.trim()
    }
    TextButton {
        text: qsTr("Refresh languages")
        onClicked: Ocr.refreshLanguages()
    }
    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        text: qsTr("Leave this empty to recognise every installed language. Install more language data with your distribution's package manager. Changes apply to your next capture.")
    }
    AiRequest {
        id: probe
    }
}
