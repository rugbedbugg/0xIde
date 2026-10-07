pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common

// The OCR & AI settings as a Nexus page, built from Nexus's own rows the way
// ServicesPage and LanguageAndRegion are: grouped sections under headers, a
// SelectRow for the backend, TextFieldRows for text, and dialog rows to confirm
// installing and removing the local model. The area picker keeps its compact
// panel (modules/areapicker/AiSettings.qml); both write the same config and
// drive the same AiRuntime and Ocr services.
PageBase {
    id: root

    // Ordered to match GlobalConfig.ai.backend: "", "external", "managed"
    readonly property var backendKeys: ["", "external", "managed"]
    readonly property list<MenuItem> backendItems: [
        MenuItem {
            text: qsTr("Off")
        },
        MenuItem {
            text: qsTr("Server")
        },
        MenuItem {
            text: qsTr("Local")
        }
    ]
    readonly property int backendIndex: Math.max(0, backendKeys.indexOf(GlobalConfig.ai.backend))
    readonly property bool external: GlobalConfig.ai.backend === "external"

    readonly property var missing: AiRuntime.info.missing ?? []
    readonly property bool installed: !!AiRuntime.info.installed
    // Held as a property: PageBase takes one content item.
    readonly property AiRequest probe: AiRequest {}

    function mib(bytes: real): int {
        return Math.round((bytes ?? 0) / 1048576);
    }

    // A typed language name or code, as the index knows it, or "".
    function languageCode(value: string): string {
        const wanted = value.trim().toLowerCase();
        return Translator.available.find(l => l.code === wanted || l.name.toLowerCase() === wanted)?.code ?? "";
    }

    // Why a typed language matched nothing: the list itself may not be loaded.
    function unknownLanguage(value: string): string {
        if (!Translator.available.length)
            return Translator.statusError || Translator.error || qsTr("The language list has not loaded yet");
        return qsTr("No offline translation model for \"%1\"").arg(value.trim());
    }
    // The answer to the latest name typed replaces the one before, whichever
    // kind it was; the row shows an error ahead of a message.
    function tellLanguage(error: string, message: string): void {
        Translator.error = error;
        Translator.message = message;
    }

    title: qsTr("OCR & AI")

    Component.onCompleted: {
        AiRuntime.refresh();
        Ocr.refreshLanguages();
        Translator.refresh();
        Speech.refresh();
    }
    Component.onDestruction: root.probe.cancel()

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        // Text recognition
        SectionHeader {
            first: true
            text: qsTr("Text recognition")
        }

        StatusRow {
            first: true
            icon: "translate"
            label: qsTr("Installed languages")
            subtext: Ocr.readiness || qsTr("Tesseract data found on this system")
            value: Ocr.engineMissing ? qsTr("Tesseract missing") : Ocr.languages.join(", ") || qsTr("None found")
            error: !!(Ocr.readiness)
        }

        TextFieldRow {
            label: qsTr("Languages to use")
            subtext: qsTr("Codes joined with +. Empty uses all")
            errorText: qsTr("Use language codes joined with +")
            placeholderText: qsTr("Languages")
            value: GlobalConfig.ai.ocrLanguages
            validate: /^\s*([A-Za-z_]+(\+[A-Za-z_]+)*)?\s*$/
            onEditingFinished: value => {
                if (field.valid && value.trim() !== GlobalConfig.ai.ocrLanguages)
                    GlobalConfig.ai.ocrLanguages = value.trim();
            }
        }

        RowButton {
            last: true
            icon: "refresh"
            text: qsTr("Rescan languages")
            subtext: qsTr("After adding or removing language packages")
            onClicked: Ocr.refreshLanguages()
        }

        // AI backend
        SectionHeader {
            text: qsTr("AI backend")
        }

        SelectRow {
            first: true
            last: !root.external
            label: qsTr("Backend")
            subtext: {
                if (root.external)
                    return qsTr("Text goes to your server, only when you press Ask AI");
                if (GlobalConfig.ai.backend === "managed")
                    return qsTr("Runs on this computer. Small and experimental");
                return qsTr("Nothing is sent anywhere");
            }
            menuItems: root.backendItems
            active: root.backendItems[root.backendIndex]
            onSelected: item => {
                const key = root.backendKeys[root.backendItems.indexOf(item)];
                if (GlobalConfig.ai.backend !== key)
                    GlobalConfig.ai.backend = key;
            }
        }

        TextFieldRow {
            visible: root.external
            label: qsTr("Server URL")
            subtext: qsTr("OpenAI-compatible chat completions")
            placeholderText: qsTr("URL")
            value: GlobalConfig.ai.backendUrl
            onEditingFinished: value => {
                if (value.trim() !== GlobalConfig.ai.backendUrl)
                    GlobalConfig.ai.backendUrl = value.trim();
            }
        }

        TextFieldRow {
            visible: root.external
            label: qsTr("Model")
            subtext: qsTr("Optional. Sent with each request")
            placeholderText: qsTr("Model")
            value: GlobalConfig.ai.model
            onEditingFinished: value => {
                if (value.trim() !== GlobalConfig.ai.model)
                    GlobalConfig.ai.model = value.trim();
            }
        }

        RowButton {
            visible: root.external
            last: true
            icon: root.probe.running ? "close" : "network_check"
            text: root.probe.running ? qsTr("Cancel test") : qsTr("Test connection")
            subtext: (root.probe.error ? qsTr("Failed: %1").arg(root.probe.error) : "") || (root.probe.status === "complete" ? qsTr("Connection succeeded") : root.probe.status || (GlobalConfig.ai.backendUrl ? qsTr("Sends a one-word request to the server") : qsTr("Enter the server URL above first")))
            disabled: !GlobalConfig.ai.backendUrl
            onClicked: {
                if (root.probe.running) {
                    root.probe.cancel();
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
                root.probe.send(GlobalConfig.ai.backendUrl, JSON.stringify(payload));
            }
        }

        // Prompt
        SectionHeader {
            text: qsTr("Prompt")
        }

        TextFieldRow {
            first: true
            last: true
            label: qsTr("System prompt")
            subtext: qsTr("Optional. Sent before the text you ask about")
            placeholderText: qsTr("Prompt")
            value: GlobalConfig.ai.systemPrompt
            onEditingFinished: value => {
                if (value !== GlobalConfig.ai.systemPrompt)
                    GlobalConfig.ai.systemPrompt = value;
            }
        }

        // Local model
        SectionHeader {
            text: qsTr("Local model")
        }

        StatusRow {
            first: true
            icon: "memory"
            label: qsTr("Status")
            subtext: {
                // The installer's own progress and errors are in full below.
                if (AiRuntime.installing)
                    return AiRuntime.stageLabel(AiRuntime.stage);
                if (installProgress.shown)
                    return root.installed ? qsTr("%1 MiB on disk").arg(root.mib(AiRuntime.info.diskBytes)) : qsTr("Not downloaded");
                if (AiRuntime.error)
                    return AiRuntime.error;
                if (AiRuntime.message)
                    return AiRuntime.message;
                if (!root.installed && root.missing.length > 0)
                    return qsTr("Install first: %1").arg(root.missing.join(", "));
                return root.installed ? qsTr("%1 MiB on disk").arg(root.mib(AiRuntime.info.diskBytes)) : qsTr("Not downloaded");
            }
            value: {
                if (AiRuntime.installing)
                    return qsTr("Installing");
                if (AiRuntime.serverState === "running")
                    return qsTr("Running");
                if (AiRuntime.serverState)
                    return AiRuntime.serverState === "stopping" ? qsTr("Stopping") : qsTr("Starting");
                return root.installed ? qsTr("Installed") : qsTr("Not installed");
            }
            error: !!(AiRuntime.error)
        }

        ConnectedRect {
            Layout.fillWidth: true
            visible: installProgress.shown
            implicitHeight: installProgress.implicitHeight + Tokens.padding.medium * 2

            AiInstallProgress {
                id: installProgress

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
            }
        }

        RowButton {
            visible: AiRuntime.installing
            last: true
            icon: "close"
            text: qsTr("Cancel installation")
            onClicked: AiRuntime.cancel()
        }

        DialogRowButton {
            visible: !AiRuntime.installing && !root.installed
            rootParent: root.flickable
            icon: "download"
            label: qsTr("Install")
            header: qsTr("Install the local model?")
            acceptLabel: qsTr("Download")
            acceptAllowed: !AiRuntime.installBlocker
            onOpenChanged: {
                if (open)
                    AiRuntime.refresh();
            }
            onAccepted: AiRuntime.install()

            content: Component {
                StyledText {
                    wrapMode: Text.Wrap
                    font: Tokens.font.body.small
                    // A disabled Download always says why.
                    color: AiRuntime.installBlocker ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                    text: AiRuntime.installBlocker || qsTr("Builds the runtime and downloads %1 MiB into %2. Needs %3 GiB free.").arg(root.mib(AiRuntime.info.downloadBytes)).arg(AiRuntime.info.destination ?? "").arg(AiRuntime.gib(AiRuntime.info.requiredBytes))
                }
            }
        }

        // Only while a server runs: there is nothing to stop otherwise.
        RowButton {
            visible: AiRuntime.serverState === "running" || AiRuntime.serverState === "starting"
            icon: "stop_circle"
            text: qsTr("Stop server")
            subtext: AiRuntime.serverLabel + qsTr(". It starts again the next time you ask")
            onClicked: AiRuntime.stop()
        }

        DialogRowButton {
            visible: root.installed && !AiRuntime.installing
            rootParent: root.flickable
            icon: "delete"
            label: qsTr("Uninstall")
            header: qsTr("Remove the local model?")
            acceptLabel: qsTr("Remove")
            onAccepted: AiRuntime.uninstall()

            content: Component {
                StyledText {
                    wrapMode: Text.Wrap
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                    text: qsTr("The model and its runtime are deleted. Server settings are kept.")
                }
            }
        }

        // Translation
        SectionHeader {
            text: qsTr("Translation")
        }

        StatusRow {
            first: true
            icon: "translate"
            label: qsTr("Installed languages")
            subtext: Translator.error || Translator.statusError || Translator.message || qsTr("Translate runs offline between these")
            value: Translator.working ? qsTr("Working") : Translator.installed.map(code => Translator.name(code)).join(", ") || qsTr("None")
            error: !!(Translator.error || Translator.statusError)
        }

        // A download, so only Enter does it: editingFinished also fires when
        // the field loses focus or the page closes, and a name typed and left
        // there must install nothing.
        TextFieldRow {
            id: addLanguage

            label: qsTr("Add a language")
            subtext: qsTr("Name or code, e.g. French, then Enter. About 160 MB each")
            placeholderText: qsTr("Language")
            value: ""
        }
        Connections {
            // A name that leads nowhere says why, under Installed languages.
            function onAccepted(): void {
                const value = addLanguage.field.text;
                const code = root.languageCode(value);
                if (code && !Translator.installed.includes(code)) {
                    Translator.install(code);
                    addLanguage.field.text = "";
                } else if (code) {
                    root.tellLanguage("", qsTr("%1 is already installed").arg(Translator.name(code)));
                } else if (value.trim()) {
                    root.tellLanguage(root.unknownLanguage(value), "");
                }
            }

            target: addLanguage.field
        }

        TextFieldRow {
            id: removeLanguage

            last: true
            label: qsTr("Remove a language")
            subtext: qsTr("Name, then Enter. Its models are deleted; English stays while any other is installed")
            placeholderText: qsTr("Language")
            value: ""
        }
        Connections {
            function onAccepted(): void {
                const value = removeLanguage.field.text;
                const code = root.languageCode(value);
                if (code && Translator.installed.includes(code)) {
                    Translator.remove(code);
                    removeLanguage.field.text = "";
                } else if (code) {
                    root.tellLanguage("", qsTr("%1 is not installed").arg(Translator.name(code)));
                } else if (value.trim()) {
                    root.tellLanguage(root.unknownLanguage(value), "");
                }
            }

            target: removeLanguage.field
        }

        // Voice dictation
        SectionHeader {
            text: qsTr("Voice dictation")
        }

        StatusRow {
            first: true
            icon: "mic"
            label: qsTr("Speech model")
            subtext: {
                // The installer's own progress and outcome are shown below.
                if (speechProgress.shown)
                    return qsTr("SUPER + SHIFT + D turns dictation on and off");
                if (Speech.error || Speech.statusError)
                    return Speech.error || Speech.statusError;
                if (Speech.message)
                    return Speech.message;
                if ((Speech.info.missing ?? []).length > 0)
                    return qsTr("Dictation needs: %1").arg(Speech.info.missing.join(", "));
                return qsTr("SUPER + SHIFT + D turns dictation on and off; each phrase is typed where you are as you pause");
            }
            value: Speech.installing ? qsTr("Installing") : Speech.working ? qsTr("Removing") : Speech.info.installed ? qsTr("Installed") : qsTr("Not installed")
            error: !!(Speech.error || Speech.statusError)
        }

        TextFieldRow {
            label: qsTr("Language")
            subtext: qsTr("A code such as en or de. auto detects it once, on the first phrase, which is slower")
            placeholderText: qsTr("en")
            value: GlobalConfig.ai.dictationLanguage
            validate: /^\s*([a-z]{2,3}|auto)?\s*$/
            errorText: qsTr("Use a two-letter code or auto")
            onEditingFinished: value => {
                const code = value.trim() || "en";
                if (field.valid && code !== GlobalConfig.ai.dictationLanguage)
                    GlobalConfig.ai.dictationLanguage = code;
            }
        }

        ConnectedRect {
            Layout.fillWidth: true
            visible: speechProgress.shown
            implicitHeight: speechProgress.implicitHeight + Tokens.padding.medium * 2

            InstallProgress {
                id: speechProgress

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: Tokens.padding.largeIncreased
                anchors.rightMargin: Tokens.padding.largeIncreased
                runtime: Speech
                what: qsTr("Speech model")
                installedHint: (Speech.info.missing ?? []).length ? qsTr("Dictation still needs: %1").arg(Speech.info.missing.join(", ")) : ""
            }
        }

        RowButton {
            visible: Speech.installing
            icon: "close"
            text: qsTr("Cancel installation")
            onClicked: Speech.cancel()
        }

        DialogRowButton {
            visible: !Speech.working && !Speech.info.installed
            rootParent: root.flickable
            icon: "download"
            label: qsTr("Install speech model")
            header: qsTr("Install the speech model?")
            acceptLabel: qsTr("Download")
            acceptAllowed: !Speech.installBlocker
            onOpenChanged: {
                if (open)
                    Speech.refresh();
            }
            onAccepted: Speech.install()

            content: Component {
                StyledText {
                    wrapMode: Text.Wrap
                    font: Tokens.font.body.small
                    // A disabled Download always says why.
                    color: Speech.installBlocker ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                    text: Speech.installBlocker || qsTr("Downloads the whisper.cpp base model, %1 MiB, into %2. Speech is transcribed on this computer.").arg(root.mib(Speech.info.downloadBytes)).arg(Speech.info.destination ?? "")
                }
            }
        }

        DialogRowButton {
            visible: !Speech.working && !!Speech.info.installed
            rootParent: root.flickable
            icon: "delete"
            label: qsTr("Remove speech model")
            header: qsTr("Remove the speech model?")
            acceptLabel: qsTr("Remove")
            onAccepted: Speech.remove()

            content: Component {
                StyledText {
                    wrapMode: Text.Wrap
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                    text: qsTr("Dictation stops working until it is installed again.")
                }
            }
        }
    }
}
