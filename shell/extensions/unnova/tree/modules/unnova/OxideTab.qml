pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.containers
import qs.services
import "unnova.js" as U

// Operate each feature through its existing service. Only local AI owns a
// persistent runtime. Model and language setup stays in Settings.
StyledFlickable {
    id: root

    contentHeight: grid.implicitHeight
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    Component.onCompleted: DesktopProfiles.refresh()

    // The dictation listener's PID, as dictate.sh records it. Trusted only
    // when that PID is running speech.py's listener right now.
    FileView {
        id: listenerPid

        path: `${Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"}/0xide-dictation/listener.pid`
        printErrors: false
    }

    Connections {
        target: Processes

        function onSampled(): void {
            listenerPid.reload();
        }
    }

    GridLayout {
        id: grid

        width: root.width
        columns: root.width >= 760 ? 2 : 1
        columnSpacing: Tokens.spacing.medium
        rowSpacing: Tokens.spacing.medium

        // Local AI
        Card {
            id: ai

            Layout.columnSpan: grid.columns
            sideActions: grid.columns > 1

            readonly property var usage: {
                Processes.samples; // re-read each sample
                return AiRuntime.serving ? Processes.usage(AiRuntime.serverPid) : ({ found: false });
            }
            readonly property var runtime: ({
                    installing: AiRuntime.installing,
                    operation: AiRuntime.operation,
                    installed: AiRuntime.info.installed,
                    serving: AiRuntime.serving,
                    stopping: AiRuntime.stopping,
                    endpoint: AiRuntime.endpoint
                })

            icon: "neurology"
            title: qsTr("Local AI")
            subtitle: AiRuntime.info.model ? `BitNet · ${String(AiRuntime.info.model).split("/").pop()}` : qsTr("BitNet")
            status: AiRuntime.error && AiRuntime.info.installed === undefined ? qsTr("Status unavailable") : U.aiState(runtime)
            statusColour: AiRuntime.endpoint && !AiRuntime.stopping ? Colours.palette.m3primary : AiRuntime.serving || AiRuntime.installing ? Colours.palette.m3tertiary : Colours.palette.m3outline
            lines: [
                AiRuntime.info.installed === undefined ? (AiRuntime.error ? qsTr("Installation status unavailable") : qsTr("Checking installation…")) : AiRuntime.info.installed ? qsTr("Model installed · starts when local AI is used") : qsTr("Model not installed · set up Local AI in Settings"),
                AiRuntime.info.contextTokens ? qsTr("Context window: %1 tokens").arg(AiRuntime.info.contextTokens) : "",
                ai.usage.found ? qsTr("%1 memory · %2 CPU · %3 process(es)").arg(U.formatBytes(ai.usage.memory)).arg(U.formatPercent(ai.usage.cpu)).arg(ai.usage.processes) : "",
                AiRuntime.endpoint ? qsTr("Endpoint: %1").arg(AiRuntime.endpoint) : "",
                AiRuntime.serving && AiRuntime.endpoint ? qsTr("Unloads itself after five minutes unused.") : "",
                (AiRuntime.info.missing ?? []).length ? qsTr("Missing: %1").arg(AiRuntime.info.missing.join(", ")) : "",
                AiRuntime.installing ? AiRuntime.message : "",
                AiRuntime.error
            ]

            AiControls {}
        }

        // Dictation
        Card {
            id: dictation

            readonly property int pid: U.pidFromFile(listenerPid.text())
            readonly property var listener: {
                Processes.samples; // re-read each sample
                const u = pid > 0 ? Processes.usage(pid) : null;
                return u && u.found && U.isListener(u.command) ? u : null;
            }
            readonly property string model: U.whisperModel(Speech.info.model)

            icon: "mic"
            title: qsTr("Dictation")
            subtitle: model ? qsTr("%1 · whisper.cpp").arg(model) : qsTr("whisper.cpp")
            status: U.dictationState({
                working: Speech.working,
                operation: Speech.operation,
                installed: Speech.info.installed
            }, listener !== null)
            statusColour: listener ? Colours.palette.m3primary : Speech.working ? Colours.palette.m3tertiary : Colours.palette.m3outline
            lines: [
                Speech.info.installed === undefined ? qsTr("Checking installation…") : Speech.info.installed ? qsTr("Model installed · loaded for dictation as needed") : qsTr("Set up the speech model in Settings to enable dictation"),
                qsTr("Language: %1").arg(GlobalConfig.ai.dictationLanguage === "auto" ? qsTr("Auto-detect") : Translator.name(GlobalConfig.ai.dictationLanguage)),
                qsTr("Use your dictation shortcut to start or stop recording"),
                listener ? qsTr("%1 memory while listening").arg(U.formatBytes(listener.memory)) : "",
                (Speech.info.missing ?? []).length ? qsTr("Missing: %1").arg(Speech.info.missing.join(", ")) : "",
                Speech.working ? Speech.message : "",
                Speech.error
            ]
        }

        // Translation
        Card {
            icon: "translate"
            title: qsTr("Translation")
            subtitle: qsTr("Argos models · offline")
            status: U.translationState({
                working: Translator.working,
                operation: Translator.operation,
                languageName: Translator.name(Translator.language),
                translating: Translator.translating
            })
            statusColour: Translator.working || Translator.translating ? Colours.palette.m3tertiary : Colours.palette.m3outline
            lines: [
                U.translationLanguages(Translator.installed.filter(c => c !== "en").map(c => Translator.name(c))),
                GlobalConfig.ai.translateFrom && GlobalConfig.ai.translateLanguage ? qsTr("Selected: %1 → %2").arg(Translator.name(GlobalConfig.ai.translateFrom)).arg(Translator.name(GlobalConfig.ai.translateLanguage)) : qsTr("Selected: no language pair configured"),
                qsTr("Runs per request; no background runtime to unload"),
                Translator.translating ? Translator.translationLabel : "",
                Translator.working ? Translator.message : "",
                Translator.error
            ]

            TranslationAction {}
        }

        // OCR
        Card {
            icon: "document_scanner"
            title: qsTr("Text recognition")
            subtitle: qsTr("Tesseract")
            status: Ocr.busy ? qsTr("Reading text") : Ocr.engineMissing ? qsTr("Unavailable") : Ocr.readiness ? qsTr("Needs language data") : qsTr("Idle")
            statusColour: Ocr.busy ? Colours.palette.m3tertiary : Ocr.readiness ? Colours.palette.m3error : Colours.palette.m3outline
            lines: [
                Ocr.readiness,
                Ocr.languages.length ? qsTr("Installed languages: %1").arg(Ocr.languages.join(", ")) : "",
                Ocr.languages.length ? qsTr("Selected languages: %1").arg(Ocr.effectiveLanguages.split("+").join(", ")) : "",
                qsTr("Runs when you capture text; no background runtime to unload"),
                Ocr.error
            ]
        }

        // Desktop profile
        Card {
            icon: "desktop_windows"
            title: qsTr("Desktop")
            subtitle: qsTr("Desktop profile")
            status: U.profileState(DesktopProfiles.active)
            statusColour: DesktopProfiles.active ? Colours.palette.m3primary : Colours.palette.m3outline
            lines: [
                DesktopProfiles.switching ? qsTr("Switching to %1…").arg(DesktopProfiles.name(DesktopProfiles.switchingTo)) : "",
                DesktopProfiles.error ? DesktopProfiles.error : DesktopProfiles.active?.description ?? qsTr("Reading the desktop profiles…"),
                qsTr("Profile selection is managed in Settings")
            ]
        }
    }

    component Card: StyledRect {
        id: card

        required property string icon
        required property string title
        property string subtitle
        required property string status
        property color statusColour: Colours.palette.m3outline
        property list<string> lines
        property bool sideActions: false
        default property alias actions: actionSlot.data

        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        implicitHeight: (sideActions ? Math.max(content.implicitHeight, actionSlot.implicitHeight) : content.implicitHeight + (actionSlot.visible ? actionSlot.implicitHeight + Tokens.spacing.small : 0)) + Tokens.padding.large * 2
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainer

        ColumnLayout {
            id: content

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.large
            anchors.rightMargin: Tokens.padding.large + (card.sideActions ? actionSlot.implicitWidth + Tokens.spacing.extraLarge : 0)
            spacing: Tokens.spacing.small

            RowLayout {
                spacing: Tokens.spacing.medium

                MaterialIcon {
                    text: card.icon
                    fill: 1
                    color: card.statusColour
                    fontStyle: Tokens.font.icon.large
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0

                    StyledText {
                        Layout.fillWidth: true
                        text: card.title
                        font: Tokens.font.title.medium
                        elide: Text.ElideRight
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: card.subtitle
                        font: Tokens.font.body.small
                        color: Colours.palette.m3onSurfaceVariant
                        elide: Text.ElideRight
                    }
                }
            }

            RowLayout {
                spacing: Tokens.spacing.small

                StyledRect {
                    implicitWidth: 8
                    implicitHeight: 8
                    radius: Tokens.rounding.full
                    color: card.statusColour
                }

                StyledText {
                    text: card.status
                    font: Tokens.font.body.medium
                    color: card.statusColour
                }
            }

            Repeater {
                model: card.lines.filter(l => l)

                StyledText {
                    required property string modelData

                    Layout.fillWidth: true
                    text: modelData
                    font: Tokens.font.body.small
                    color: Colours.palette.m3onSurfaceVariant
                    wrapMode: Text.WordWrap
                }
            }
        }

        Item {
            id: actionSlot

            anchors.left: card.sideActions ? undefined : parent.left
            anchors.right: card.sideActions ? parent.right : undefined
            anchors.top: card.sideActions ? undefined : content.bottom
            anchors.verticalCenter: card.sideActions ? parent.verticalCenter : undefined
            anchors.leftMargin: Tokens.padding.large
            anchors.rightMargin: Tokens.padding.large
            anchors.topMargin: Tokens.spacing.small
            implicitWidth: childrenRect.width
            implicitHeight: childrenRect.height
            visible: children.length > 0
        }
    }
}
