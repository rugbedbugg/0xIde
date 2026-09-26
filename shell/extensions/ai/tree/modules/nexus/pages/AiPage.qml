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

    title: qsTr("OCR & AI")

    Component.onCompleted: {
        AiRuntime.refresh();
        Ocr.refreshLanguages();
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

        InfoRow {
            first: true
            icon: "translate"
            label: qsTr("Installed languages")
            subtext: qsTr("Tesseract data found on this system")
            value: Ocr.languages.join(", ") || qsTr("None found")
        }

        TextFieldRow {
            label: qsTr("Languages to use")
            subtext: qsTr("Codes joined with +. Empty uses all")
            errorText: qsTr("Use language codes joined with +")
            placeholderText: qsTr("All")
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
            subtext: qsTr("An OpenAI-compatible chat completions endpoint")
            placeholderText: "http://localhost:8080/v1/chat/completions"
            value: GlobalConfig.ai.backendUrl
            onEditingFinished: value => {
                if (value.trim() !== GlobalConfig.ai.backendUrl)
                    GlobalConfig.ai.backendUrl = value.trim();
            }
        }

        TextFieldRow {
            visible: root.external
            label: qsTr("Model")
            subtext: qsTr("Sent with each request, if your server needs one")
            placeholderText: qsTr("Optional")
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
            subtext: root.probe.error || (root.probe.status === "complete" ? qsTr("Connection succeeded") : root.probe.status || qsTr("Sends a one-word request to the server"))
            subLabel.color: root.probe.error ? Colours.palette.m3error : Colours.palette.m3outline
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
            subtext: qsTr("Sent before the text you ask about")
            placeholderText: qsTr("Optional")
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

        InfoRow {
            first: true
            icon: "memory"
            label: qsTr("Status")
            subtext: {
                if (AiRuntime.error)
                    return AiRuntime.error;
                if (AiRuntime.message)
                    return AiRuntime.message;
                if (!root.installed && root.missing.length > 0)
                    return qsTr("Install first: %1").arg(root.missing.join(", "));
                return root.installed ? qsTr("%1 MiB on disk").arg(root.mib(AiRuntime.info.diskBytes)) : qsTr("Not downloaded");
            }
            value: AiRuntime.installing ? qsTr("Installing") : root.installed ? qsTr("Installed") : qsTr("Not installed")
            iconColour: AiRuntime.error ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
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
            acceptAllowed: !!AiRuntime.info.destination && root.missing.length === 0 && (AiRuntime.info.freeBytes ?? 0) >= (AiRuntime.info.requiredBytes ?? 0)
            onOpenChanged: {
                if (open)
                    AiRuntime.refresh();
            }
            onAccepted: AiRuntime.install()

            content: Component {
                StyledText {
                    wrapMode: Text.Wrap
                    font: Tokens.font.body.small
                    color: root.missing.length > 0 ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
                    text: {
                        if (root.missing.length > 0)
                            return qsTr("Install first: %1").arg(root.missing.join(", "));
                        return qsTr("Downloads %1 MiB into %2. %3 MiB free.").arg(root.mib(AiRuntime.info.downloadBytes)).arg(AiRuntime.info.destination ?? "").arg(root.mib(AiRuntime.info.freeBytes));
                    }
                }
            }
        }

        RowButton {
            visible: root.installed && !AiRuntime.installing
            icon: "stop_circle"
            text: qsTr("Stop server")
            subtext: qsTr("It starts again the next time you ask")
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
    }
}
