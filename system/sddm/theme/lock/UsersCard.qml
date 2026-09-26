pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import "../components"

// Who is logging in, in the place the lockscreen gives the notification dock,
// with the same extra-large bottom-right corner. Each account is a row with
// its picture in a circle; the chosen one sits on secondaryContainer.
StyledRect {
    id: root

    property int currentIndex
    signal selected(int index)

    radius: Tokens.rounding.medium
    bottomRightRadius: Tokens.rounding.extraLarge
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
                text: "group"
                color: Colours.palette.m3primary
                size: Tokens.font.iconMedium
            }

            StyledText {
                Layout.fillWidth: true
                text: qsTr("Accounts")
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
            model: userModel
            currentIndex: root.currentIndex

            delegate: StyledRect {
                id: row

                required property int index
                required property string name
                required property string realName
                required property string icon
                readonly property bool current: index === root.currentIndex

                width: list.width
                implicitHeight: avatar.implicitHeight + Tokens.padding.small * 2
                radius: height / 2
                color: current ? Colours.palette.m3secondaryContainer : "transparent"

                StateLayer {
                    color: row.current ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                    onClicked: root.selected(row.index)
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: Tokens.padding.small
                    anchors.rightMargin: Tokens.padding.large
                    spacing: Tokens.spacing.medium

                    Item {
                        id: avatar

                        implicitWidth: 36
                        implicitHeight: 36

                        Rectangle {
                            id: avatarBg

                            anchors.fill: parent
                            radius: width / 2
                            color: row.current ? Colours.palette.m3primary : Colours.palette.m3surfaceContainerHighest
                            layer.enabled: true
                        }

                        MaterialIcon {
                            anchors.centerIn: parent
                            text: "person"
                            fill: 1
                            color: row.current ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                            size: Tokens.font.iconSmall
                            visible: face.status !== Image.Ready
                        }

                        Image {
                            id: face

                            property int attempt

                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            cache: false
                            sourceSize.width: width
                            sourceSize.height: height
                            source: attempt === 0 ? Qt.resolvedUrl("../faces/" + row.name) : attempt === 1 ? row.icon : ""
                            onStatusChanged: {
                                if (status === Image.Error)
                                    attempt++;
                            }
                            visible: false
                        }

                        MultiEffect {
                            anchors.fill: parent
                            source: face
                            visible: face.status === Image.Ready
                            maskEnabled: true
                            maskSource: avatarBg
                            maskThresholdMin: 0.5
                            maskSpreadAtMin: 1
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0

                        StyledText {
                            Layout.fillWidth: true
                            text: row.realName || row.name
                            elide: Text.ElideRight
                            color: row.current ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurface
                            font.pointSize: Tokens.font.bodyMedium
                        }

                        StyledText {
                            Layout.fillWidth: true
                            visible: row.realName && row.realName !== row.name
                            text: row.name
                            elide: Text.ElideRight
                            color: row.current ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                        }
                    }
                }
            }
        }
    }
}
