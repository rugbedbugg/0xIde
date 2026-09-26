pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../components"

// Whose password the field below wants: the account's picture and name over
// an underline, as the shell's text fields draw their resting state. The line
// thickens into primary under the pointer and while the account menu is open;
// with more than one account, the chevron says it opens one.
Item {
    id: root

    required property real scaleFactor
    property string userName
    property string displayName
    property string modelIcon
    property bool expandable
    property bool expanded
    readonly property bool lit: expanded || (expandable && mouse.containsMouse)

    signal clicked

    implicitHeight: row.implicitHeight + Tokens.padding.small * 2

    StateLayer {
        id: mouse

        radius: Tokens.rounding.small
        disabled: !root.expandable
        onClicked: root.clicked()
    }

    RowLayout {
        id: row

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Tokens.spacing.large

        Avatar {
            Layout.preferredWidth: Math.round(40 * root.scaleFactor)
            Layout.preferredHeight: Math.round(40 * root.scaleFactor)
            userName: root.userName
            modelIcon: root.modelIcon
            colour: root.lit ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainerHigh
            onColour: root.lit ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
        }

        StyledText {
            Layout.fillWidth: true

            animate: true
            text: root.displayName
            elide: Text.ElideRight
            color: Colours.palette.m3onSurface
            font.pointSize: Tokens.font.labelLarge * root.scaleFactor
            font.weight: Font.DemiBold
        }

        MaterialIcon {
            Layout.rightMargin: Tokens.padding.small
            visible: root.expandable
            text: "expand_more"
            color: root.lit ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
            size: Tokens.font.iconMedium * root.scaleFactor
            rotation: root.expanded ? 180 : 0

            Behavior on rotation {
                Anim {}
            }
        }
    }

    StyledRect {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        implicitHeight: root.lit ? 2 : 1
        radius: height / 2
        color: root.lit ? Colours.palette.m3primary : Colours.palette.m3outline

        Behavior on implicitHeight {
            Anim {
                type: Anim.FastSpatial
            }
        }
    }
}
