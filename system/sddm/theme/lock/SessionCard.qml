pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../components"

// Which session to start, in the place the lockscreen gives the media card.
// Each session is a full-round row; the chosen one sits on secondaryContainer.
StyledRect {
    id: root

    property int currentIndex
    signal selected(int index)

    radius: Tokens.rounding.medium
    bottomLeftRadius: Tokens.rounding.extraLarge
    color: Colours.palette.m3surfaceContainer

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: Tokens.padding.large
        spacing: Tokens.spacing.small

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: Tokens.padding.small
            spacing: Tokens.spacing.medium

            MaterialIcon {
                text: "desktop_windows"
                color: Colours.palette.m3primary
                size: Tokens.font.iconMedium
            }

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Session")
                font.pointSize: Tokens.font.titleMedium
                font.weight: Font.Medium
            }
        }

        ListView {
            id: list

            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: Tokens.spacing.extraSmall
            boundsBehavior: Flickable.StopAtBounds
            model: sessionModel
            currentIndex: root.currentIndex

            delegate: StyledRect {
                id: row

                required property int index
                required property string name
                required property string comment
                readonly property bool current: index === root.currentIndex

                width: list.width
                implicitHeight: rowLayout.implicitHeight + Tokens.padding.medium * 2
                radius: height / 2
                color: current ? Colours.palette.m3secondaryContainer : "transparent"

                StateLayer {
                    color: row.current ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                    onClicked: root.selected(row.index)
                }

                RowLayout {
                    id: rowLayout

                    anchors.fill: parent
                    anchors.leftMargin: Tokens.padding.large
                    anchors.rightMargin: Tokens.padding.large
                    spacing: Tokens.spacing.medium

                    MaterialIcon {
                        text: row.current ? "radio_button_checked" : "radio_button_unchecked"
                        fill: row.current ? 1 : 0
                        color: row.current ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                        size: Tokens.font.iconSmall
                    }

                    StyledText {
                        Layout.fillWidth: true
                        text: row.name
                        elide: Text.ElideRight
                        color: row.current ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                        font.pointSize: Tokens.font.bodyMedium
                    }
                }
            }
        }
    }
}
