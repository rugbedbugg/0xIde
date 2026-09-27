pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.components.effects
import qs.services

// The ways a region can be searched, offered inside the selector rather than
// on separate keys: the web by its text or by the image, or the AI. Illogical
// Impulse puts the same choice in a toolbar at the bottom of its own selector,
// and here the choice also decides what leaves the machine, so it is worth
// being able to change your mind without closing the selector and pressing
// something else.
Item {
    id: root

    required property string mode

    signal selected(string mode)

    implicitWidth: card.implicitWidth
    implicitHeight: card.implicitHeight

    StyledText {
        id: localSizer

        visible: false
        font: Tokens.font.label.small
        text: qsTr("Read on this computer; only the text is searched")
    }
    StyledText {
        id: uploadSizer

        visible: false
        font: Tokens.font.label.small
        text: qsTr("Uploads the image, and asks first")
    }
    StyledText {
        id: aiSizer

        visible: false
        font: Tokens.font.label.small
        text: qsTr("Read on this computer, then ask the AI about it")
    }

    Elevation {
        anchors.fill: card
        radius: card.radius
        level: 2
    }

    StyledRect {
        id: card

        radius: Tokens.rounding.large
        color: Colours.palette.m3surfaceContainer
        implicitWidth: column.implicitWidth + Tokens.padding.large * 2
        implicitHeight: column.implicitHeight + Tokens.padding.medium * 2

        ColumnLayout {
            id: column

            anchors.centerIn: parent
            spacing: Tokens.spacing.extraSmall

            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: Tokens.spacing.extraSmall

                IconTextButton {
                    icon: "crop_free"
                    text: qsTr("Text")
                    isToggle: true
                    checked: root.mode === "rectangle"
                    onClicked: root.selected("rectangle")
                }
                IconTextButton {
                    icon: "gesture"
                    text: qsTr("Image")
                    isToggle: true
                    checked: root.mode === "circle"
                    onClicked: root.selected("circle")
                }
                IconTextButton {
                    icon: "auto_awesome"
                    text: qsTr("Ask AI")
                    isToggle: true
                    checked: root.mode === "ai"
                    onClicked: root.selected("ai")
                }
            }
            // Which one uploads is the thing worth knowing, so it is stated
            // rather than left to the icon. Every caption is measured and the
            // widest fixes the width, because a card that resizes when you
            // switch moves the other button out from under the pointer.
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Math.max(localSizer.implicitWidth, uploadSizer.implicitWidth, aiSizer.implicitWidth)
                horizontalAlignment: Text.AlignHCenter
                font: Tokens.font.label.small
                color: Colours.palette.m3outline
                text: root.mode === "circle" ? uploadSizer.text : root.mode === "ai" ? aiSizer.text : localSizer.text
            }
        }
    }
}
