pragma ComponentBehavior: Bound

import QtQuick
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
    property string removeLanguage: ""

    readonly property var missing: AiRuntime.info.missing ?? []
    readonly property int backendIndex: GlobalConfig.ai.backend === "managed" ? 2 : GlobalConfig.ai.backend === "external" ? 1 : 0

    spacing: Tokens.spacing.small

    Component.onDestruction: probe.cancel()

    StyledText {
        Layout.fillWidth: true
        text: qsTr("AI backend")
        font: Tokens.font.title.small
    }

    // A row of toggles rather than a dropdown: there are three options, they
    // are short, and a popup inside a scrolling view would be clipped by it.
    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        Repeater {
            model: [qsTr("Off"), qsTr("Server"), qsTr("Local")]

            TextButton {
                required property int index
                required property string modelData

                text: modelData
                isToggle: true
                checked: root.backendIndex === index
                onClicked: if (GlobalConfig.ai.backend !== ["", "external", "managed"][index])
                    GlobalConfig.ai.backend = ["", "external", "managed"][index]
            }
        }
        Item {
            Layout.fillWidth: true
        }
    }
    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: Colours.palette.m3outline
        font: Tokens.font.label.large
        text: {
            if (GlobalConfig.ai.backend === "external")
                return qsTr("Text goes to this URL, only when you press Ask AI.");
            if (GlobalConfig.ai.backend === "managed")
                return qsTr("Runs on this computer. Small and experimental.");
            return qsTr("Nothing is sent anywhere until you pick a backend.");
        }
    }

    StyledTextField {
        Layout.fillWidth: true
        visible: GlobalConfig.ai.backend === "external"
        placeholderText: qsTr("Chat completions URL")
        text: GlobalConfig.ai.backendUrl
        onEditingFinished: if (text.trim() !== GlobalConfig.ai.backendUrl)
            GlobalConfig.ai.backendUrl = text.trim()
    }
    StyledTextField {
        Layout.fillWidth: true
        visible: GlobalConfig.ai.backend === "external"
        placeholderText: qsTr("Model name (optional)")
        text: GlobalConfig.ai.model
        onEditingFinished: if (text.trim() !== GlobalConfig.ai.model)
            GlobalConfig.ai.model = text.trim()
    }
    StyledTextField {
        Layout.fillWidth: true
        placeholderText: qsTr("System prompt (optional)")
        text: GlobalConfig.ai.systemPrompt
        onEditingFinished: if (text !== GlobalConfig.ai.systemPrompt)
            GlobalConfig.ai.systemPrompt = text
    }
    RowLayout {
        Layout.fillWidth: true
        visible: GlobalConfig.ai.backend === "external"
        spacing: Tokens.spacing.small

        TextButton {
            type: TextButton.Tonal
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
            font: Tokens.font.label.large
            color: probe.error ? Colours.palette.m3error : Colours.palette.m3outline
            text: probe.error || (probe.status === "complete" ? qsTr("Connection succeeded") : probe.status)
        }
    }

    StyledText {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.medium
        text: qsTr("Local model")
        font: Tokens.font.title.small
    }
    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: Colours.palette.m3outline
        font: Tokens.font.label.large
        text: AiRuntime.installing ? qsTr("Installing") : AiRuntime.serverLabel || (AiRuntime.info.installed ? qsTr("Installed, %1 MiB; starts when you ask").arg(Math.round((AiRuntime.info.diskBytes ?? 0) / 1048576)) : qsTr("Not installed"))
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.extraSmall

        TextButton {
            type: TextButton.Text
            text: qsTr("Refresh")
            onClicked: AiRuntime.refresh()
        }
        TextButton {
            type: TextButton.Text
            visible: !AiRuntime.info.installed && !AiRuntime.installing
            text: qsTr("Install")
            onClicked: {
                AiRuntime.refresh();
                root.confirmInstall = true;
            }
        }
        TextButton {
            type: TextButton.Text
            visible: AiRuntime.installing
            text: qsTr("Cancel installation")
            onClicked: AiRuntime.cancel()
        }
        TextButton {
            type: TextButton.Text
            visible: AiRuntime.serverState === "running" || AiRuntime.serverState === "starting"
            text: qsTr("Stop server")
            onClicked: AiRuntime.stop()
        }
        TextButton {
            type: TextButton.Text
            visible: !!AiRuntime.info.installed
            text: qsTr("Uninstall")
            onClicked: root.confirmRemove = true
        }
        Item {
            Layout.fillWidth: true
        }
    }

    // Only shown when something is actually missing, rather than as a standing
    // paragraph about tools most people already have.
    StyledText {
        Layout.fillWidth: true
        visible: !AiRuntime.info.installed && root.missing.length > 0 && !root.confirmInstall
        wrapMode: Text.Wrap
        color: Colours.palette.m3error
        font: Tokens.font.label.large
        text: qsTr("Install first: %1").arg(root.missing.join(", "))
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.confirmInstall && !!AiRuntime.info.destination
        wrapMode: Text.Wrap
        font: Tokens.font.label.large
        text: qsTr("Builds the runtime and downloads %1 MiB into %2. Needs %3 GiB free.").arg(Math.round((AiRuntime.info.downloadBytes ?? 0) / 1048576)).arg(AiRuntime.info.destination ?? "").arg(AiRuntime.gib(AiRuntime.info.requiredBytes))
    }
    RowLayout {
        visible: root.confirmInstall
        spacing: Tokens.spacing.small

        TextButton {
            type: TextButton.Tonal
            text: qsTr("Download")
            disabled: !!AiRuntime.installBlocker
            onClicked: {
                root.confirmInstall = false;
                AiRuntime.install();
            }
        }
        TextButton {
            type: TextButton.Text
            text: qsTr("Cancel")
            onClicked: root.confirmInstall = false
        }
    }
    // A disabled Download always says why.
    StyledText {
        Layout.fillWidth: true
        visible: root.confirmInstall && !!AiRuntime.installBlocker
        wrapMode: Text.Wrap
        font: Tokens.font.label.large
        color: Colours.palette.m3error
        text: AiRuntime.installBlocker
    }
    AiInstallProgress {
        id: progress

        Layout.fillWidth: true
    }

    StyledText {
        Layout.fillWidth: true
        visible: root.confirmRemove
        wrapMode: Text.Wrap
        font: Tokens.font.label.large
        text: qsTr("Remove the local model and its runtime? Server settings are kept.")
    }
    RowLayout {
        visible: root.confirmRemove
        spacing: Tokens.spacing.small

        TextButton {
            type: TextButton.Tonal
            text: qsTr("Remove")
            onClicked: {
                root.confirmRemove = false;
                AiRuntime.uninstall();
            }
        }
        TextButton {
            type: TextButton.Text
            text: qsTr("Keep")
            onClicked: root.confirmRemove = false
        }
    }
    // Whatever is not the installer's: the status check, the server, removal.
    StyledText {
        Layout.fillWidth: true
        visible: !progress.shown && !(root.confirmInstall && AiRuntime.installBlocker) && !!(AiRuntime.error || AiRuntime.message)
        wrapMode: Text.Wrap
        font: Tokens.font.label.large
        color: AiRuntime.error ? Colours.palette.m3error : Colours.palette.m3outline
        text: AiRuntime.error || AiRuntime.message
    }

    // Offline translation: each language is a pair of models through English,
    // so English appears as soon as any other language is installed.
    StyledText {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.medium
        text: qsTr("Translation languages")
        font: Tokens.font.title.small
    }
    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: Colours.palette.m3outline
        font: Tokens.font.label.large
        text: Translator.installed.length ? qsTr("Translate runs offline between these. Select one to remove it.") : qsTr("None installed. Each language is about 160 MB and translates offline to and from every other installed one.")
    }
    Flow {
        Layout.fillWidth: true
        visible: Translator.installed.length > 0
        spacing: Tokens.spacing.extraSmall

        Repeater {
            model: Translator.installed

            TextButton {
                required property string modelData

                type: TextButton.Tonal
                text: Translator.name(modelData)
                disabled: Translator.working || modelData === "en"
                onClicked: root.removeLanguage = modelData
            }
        }
    }
    RowLayout {
        visible: !!root.removeLanguage
        spacing: Tokens.spacing.small

        StyledText {
            font: Tokens.font.label.large
            text: qsTr("Remove %1?").arg(Translator.name(root.removeLanguage))
        }
        TextButton {
            type: TextButton.Tonal
            text: qsTr("Remove")
            onClicked: {
                Translator.remove(root.removeLanguage);
                root.removeLanguage = "";
            }
        }
        TextButton {
            type: TextButton.Text
            text: qsTr("Keep")
            onClicked: root.removeLanguage = ""
        }
    }
    StyledTextField {
        id: languageFilter

        Layout.fillWidth: true
        placeholderText: qsTr("Add a language, e.g. French")
    }
    Flow {
        Layout.fillWidth: true
        visible: !!languageFilter.text.trim()
        spacing: Tokens.spacing.extraSmall

        Repeater {
            model: Translator.available.filter(l => !Translator.installed.includes(l.code) && l.code !== "en" && l.name.toLowerCase().includes(languageFilter.text.trim().toLowerCase()))

            TextButton {
                required property var modelData

                type: TextButton.Text
                text: modelData.name
                disabled: Translator.working
                onClicked: {
                    Translator.install(modelData.code);
                    languageFilter.text = "";
                }
            }
        }
    }
    StyledText {
        Layout.fillWidth: true
        visible: !!(Translator.error || Translator.statusError || Translator.message || Translator.working)
        wrapMode: Text.Wrap
        font: Tokens.font.label.large
        color: Translator.error || Translator.statusError ? Colours.palette.m3error : Colours.palette.m3outline
        text: Translator.error || Translator.statusError || Translator.message || qsTr("Working...")
    }

    StyledText {
        Layout.fillWidth: true
        Layout.topMargin: Tokens.spacing.medium
        text: qsTr("OCR languages")
        font: Tokens.font.title.small
    }
    StyledText {
        Layout.fillWidth: true
        wrapMode: Text.Wrap
        color: Ocr.readiness ? Colours.palette.m3error : Colours.palette.m3outline
        font: Tokens.font.label.large
        text: Ocr.engineMissing ? Ocr.readiness : [qsTr("Installed: %1").arg(Ocr.languages.join(", ") || qsTr("none found")), Ocr.readiness].filter(t => t).join("\n")
    }
    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        StyledTextField {
            Layout.fillWidth: true
            placeholderText: qsTr("e.g. eng+deu. Empty uses all installed")
            text: GlobalConfig.ai.ocrLanguages
            onEditingFinished: if (text.trim() !== GlobalConfig.ai.ocrLanguages)
                GlobalConfig.ai.ocrLanguages = text.trim()
        }
        TextButton {
            type: TextButton.Text
            text: qsTr("Refresh")
            onClicked: Ocr.refreshLanguages()
        }
    }

    AiRequest {
        id: probe
    }
}
