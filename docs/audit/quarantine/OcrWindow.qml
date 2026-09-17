pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Caelestia.Config
import qs.components
import qs.components.containers
import qs.components.controls
import qs.components.effects
import qs.services

Scope {
    StyledWindow {
        id: window
        name: "ocr-window"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.exclusionMode: ExclusionMode.Ignore
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

        anchors.top: true
        anchors.bottom: true
        anchors.left: true
        anchors.right: true

        property string ocrText: ""

        readonly property int maxWidth: Math.min(screen.width * 0.6, 1100)
        readonly property int maxHeight: screen.height * 0.6

        // Forces a colour fully opaque regardless of the shell's global
        // transparency setting -- this popup should always be solid.
        function solid(c: color): color {
            return Qt.rgba(c.r, c.g, c.b, 1)
        }

        function showText(text: string): void {
            ocrText = text
            visible = true
            card.forceActiveFocus()
        }

        function hide(): void {
            ocrText = ""
            visible = false
        }

        function copyToClipboard(): void {
            Quickshell.execDetached(["wl-copy", ocrText])
            Quickshell.execDetached(["notify-send", "-a", "caelestia-ocr", "-u", "low", "Text copied", "OCR text copied to clipboard"])
        }

        visible: ocrText.length > 0

        // Layer-shell surfaces fill their anchored edges and have no x/y of
        // their own, so the card is centred inside the fullscreen window
        // rather than the window itself being moved. Keys also needs an
        // actual focused Item, which the PanelWindow itself is not.
        Item {
            id: card
            focus: true
            anchors.centerIn: parent
            readonly property int margin: Tokens.spacing.extraLarge
            width: window.maxWidth
            height: Math.min(contentItem.implicitHeight + margin * 2, window.maxHeight)

            Keys.onEscapePressed: window.hide()

            // Elevation is a drop shadow meant to sit behind the card as its
            // own sibling (see e.g. Menu.qml) -- applying it via layer.effect
            // on the background Rectangle replaced the rectangle's own
            // rendering with just the (translucent) shadow, which is why the
            // card looked like it had no solid background at all.
            Elevation {
                anchors.fill: parent
                level: 3
            }

            // A true backdrop behind the whole card, not a layout child
            // competing with the text/buttons for their own row of space.
            Rectangle {
                id: background
                anchors.fill: parent
                radius: Tokens.rounding.large
                color: window.solid(Colours.palette.m3surfaceContainer)
                border.color: Colours.palette.m3outlineVariant
                border.width: 1
            }

        ColumnLayout {
            id: contentItem
            anchors.fill: parent
            anchors.margins: card.margin
            spacing: Tokens.spacing.medium

            // Nested rounded panel (the same surfaceContainer/surfaceContainerHigh
            // pairing caelestia's own dialogs use, e.g. DialogButtons.qml) so the
            // extracted text reads as its own section, distinct from the button row.
            Rectangle {
                id: textPanel
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.minimumHeight: 200
                radius: Tokens.rounding.medium
                color: window.solid(Colours.palette.m3surfaceContainerHigh)

                ScrollView {
                    anchors.fill: parent
                    clip: true

                    TextArea {
                        id: textArea
                        readOnly: true
                        selectByMouse: true
                        text: window.ocrText
                        wrapMode: TextArea.Wrap
                        font: Tokens.font.mono.medium
                        color: Colours.palette.m3onSurface
                        background: Rectangle { color: "transparent" }
                        padding: Tokens.spacing.medium
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Tokens.spacing.small

                Item { Layout.fillWidth: true }

                IconTextButton {
                    id: copyBtn
                    text: "Copy"
                    icon: "content_copy"
                    onClicked: window.copyToClipboard()
                }

                IconTextButton {
                    id: closeBtn
                    text: "Close"
                    icon: "close"
                    onClicked: window.hide()
                }
            }
        }
        }

        IpcHandler {
            target: "ocrwindow"
            function showText(text: string): void {
                window.showText(text)
            }
        }
    }
}