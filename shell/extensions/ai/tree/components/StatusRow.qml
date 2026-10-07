pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.services
import qs.modules.nexus.common

// A Nexus InfoRow whose subtext wraps instead of being cut to one line, for
// rows whose subtext can be the reason something does not work. With error
// set, the icon and subtext are in the error colour.
ConnectedRect {
    id: root

    property alias label: label.text
    property string subtext
    property alias value: value.text
    property string icon
    property bool error

    Layout.fillWidth: true
    implicitHeight: rowLayout.implicitHeight + rowLayout.anchors.margins * 2

    RowLayout {
        id: rowLayout

        anchors.fill: parent
        anchors.margins: Tokens.padding.medium
        anchors.leftMargin: Tokens.padding.largeIncreased
        anchors.rightMargin: Tokens.padding.largeIncreased
        spacing: Tokens.spacing.medium

        MaterialIcon {
            visible: !!root.icon
            text: root.icon
            color: root.error ? Colours.palette.m3error : Colours.palette.m3onSurfaceVariant
            fontStyle: Tokens.font.icon.small
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0

            StyledText {
                id: label

                Layout.fillWidth: true
                font: Tokens.font.body.small
                elide: Text.ElideRight
            }

            StyledText {
                Layout.fillWidth: true
                visible: !!root.subtext
                text: root.subtext
                color: root.error ? Colours.palette.m3error : Colours.palette.m3outline
                font: Tokens.font.label.small
                wrapMode: Text.Wrap
            }
        }

        StyledText {
            id: value

            Layout.maximumWidth: root.width / 2
            horizontalAlignment: Text.AlignRight
            color: Colours.palette.m3onSurfaceVariant
            font: Tokens.font.body.small
            elide: Text.ElideRight
        }
    }
}
