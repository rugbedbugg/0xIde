pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Caelestia.Config
import Caelestia.Services
import qs.components
import qs.components.containers
import qs.components.controls
import qs.services
import "unnova.js" as U

// What 0xIde itself runs, by what it is rather than by PID. Each card shows
// only what its service can establish, and offers an action only where the
// service already has one: the local AI server can be unloaded and restarted;
// dictation, translation and OCR run a helper per use, so there is nothing
// resident to manage, and the desktop profile is switched in Theme settings.
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
        columns: Math.max(1, Math.floor(root.width / 380))
        columnSpacing: Tokens.spacing.medium
        rowSpacing: Tokens.spacing.medium

        // Local AI
        Card {
            id: ai

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
            readonly property var can: U.aiCan(runtime)

            icon: "neurology"
            title: qsTr("Local AI")
            subtitle: AiRuntime.info.model ? `BitNet · ${String(AiRuntime.info.model).split("/").pop()}` : qsTr("BitNet")
            status: U.aiState(runtime)
            statusColour: AiRuntime.endpoint && !AiRuntime.stopping ? Colours.palette.m3primary : AiRuntime.serving || AiRuntime.installing ? Colours.palette.m3tertiary : Colours.palette.m3outline
            lines: [
                ai.usage.found ? qsTr("%1 memory · %2 CPU · %3 process(es)").arg(U.formatBytes(ai.usage.memory)).arg(U.formatPercent(ai.usage.cpu)).arg(ai.usage.processes) : "",
                AiRuntime.endpoint ? AiRuntime.endpoint : "",
                AiRuntime.serving && AiRuntime.endpoint ? qsTr("Unloads itself after five minutes unused.") : "",
                AiRuntime.installing ? AiRuntime.message : ""
            ]

            RowLayout {
                spacing: Tokens.spacing.small

                IconTextButton {
                    icon: "eject"
                    text: qsTr("Unload")
                    type: IconTextButton.Tonal
                    isRound: true
                    disabled: !ai.can.unload
                    onClicked: AiRuntime.stop()
                }

                IconTextButton {
                    icon: "restart_alt"
                    text: qsTr("Restart")
                    type: IconTextButton.Tonal
                    isRound: true
                    disabled: !ai.can.restart
                    onClicked: AiRuntime.restart()
                }
            }
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
                Speech.info.installed ? qsTr("Model installed") : "",
                listener ? qsTr("%1 memory while listening").arg(U.formatBytes(listener.memory)) : "",
                (Speech.info.missing ?? []).length ? qsTr("Missing: %1").arg(Speech.info.missing.join(", ")) : "",
                Speech.working ? Speech.message : ""
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
                U.translationLanguages(Translator.installed.map(c => Translator.name(c))),
                Translator.working ? Translator.message : ""
            ]
        }

        // OCR
        Card {
            icon: "document_scanner"
            title: qsTr("Text recognition")
            subtitle: qsTr("Tesseract")
            status: Ocr.busy ? qsTr("Reading text") : qsTr("Idle")
            statusColour: Ocr.busy ? Colours.palette.m3tertiary : Colours.palette.m3outline
            lines: [Ocr.languages.length ? qsTr("Languages: %1").arg(Ocr.effectiveLanguages.split("+").join(", ")) : ""]
        }

        // Desktop profile
        Card {
            icon: "desktop_windows"
            title: qsTr("Desktop")
            subtitle: qsTr("Desktop profile")
            status: U.profileState(DesktopProfiles.active)
            statusColour: DesktopProfiles.active ? Colours.palette.m3primary : Colours.palette.m3outline
            lines: [DesktopProfiles.active?.description ?? ""]
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
        default property alias actions: actionSlot.data

        Layout.fillWidth: true
        Layout.alignment: Qt.AlignTop
        implicitHeight: content.implicitHeight + Tokens.padding.large * 2
        radius: Tokens.rounding.large
        color: Colours.tPalette.m3surfaceContainer

        ColumnLayout {
            id: content

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: Tokens.padding.large
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

            Item {
                id: actionSlot

                Layout.topMargin: children.length ? Tokens.spacing.small : 0
                implicitWidth: childrenRect.width
                implicitHeight: childrenRect.height
                visible: children.length > 0
            }
        }
    }
}
