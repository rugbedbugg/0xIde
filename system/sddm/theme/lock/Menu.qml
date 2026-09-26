pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import "../components"

// components/controls/Menu.qml from the shell: a surfaceContainerLow card at
// elevation 2 that unfolds from the edge it is attached to, rows whose corners
// round off at the ends of the list, and the chosen row on tertiaryContainer
// with the tighter medium rounding. It fills the screen while open, so a click
// anywhere else closes it.
//
// The shell's menus are only for the pointer; here the password field keeps
// the keyboard, so Main hands the arrow keys, Enter and Escape to whichever
// menu is open.
MouseArea {
    id: root

    required property Item attachTo
    // Unfold upwards from the top edge of attachTo, instead of down from its
    // bottom edge.
    property bool above
    property real minWidth: 200
    // [{ icon, text, detail }]
    property var items: []
    property int activeIndex: -1
    property int keyIndex: -1
    property bool expanded

    signal selected(int index)

    function open(): void {
        const p = attachTo.mapToItem(root, 0, 0);
        menu.x = Math.min(p.x, root.width - menu.width - Tokens.padding.large);
        menu.y = above ? p.y - menu.height - Tokens.spacing.small : p.y + attachTo.height + Tokens.spacing.small;
        keyIndex = activeIndex;
        expanded = true;
    }

    function move(delta: int): void {
        if (items.length > 0)
            keyIndex = ((keyIndex < 0 ? (delta > 0 ? -1 : 0) : keyIndex) + delta + items.length) % items.length;
    }

    function choose(index: int): void {
        if (index < 0 || index >= items.length)
            return;
        expanded = false;
        selected(index);
    }

    anchors.fill: parent

    enabled: expanded
    hoverEnabled: expanded
    cursorShape: expanded ? Qt.ArrowCursor : undefined
    onClicked: expanded = false

    visible: opacity > 0
    opacity: expanded ? 1 : 0
    layer.enabled: opacity < 1

    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }

    Item {
        id: menu

        implicitWidth: Math.max(root.minWidth, column.implicitWidth + column.anchors.margins * 2)
        implicitHeight: column.implicitHeight + column.anchors.margins * 2

        transform: Scale {
            yScale: root.expanded ? 1 : 0.1
            origin.y: root.above ? menu.height : 0

            Behavior on yScale {
                Anim {}
            }
        }

        // components/effects/Elevation.qml at level 2.
        RectangularShadow {
            readonly property real dp: 3

            anchors.fill: parent
            radius: bg.radius
            color: Qt.alpha(Colours.palette.m3shadow, 0.7)
            blur: (dp * 5) ** 0.7
            spread: -dp * 0.3 + (dp * 0.1) ** 2
            offset.y: dp / 2
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
        }

        StyledRect {
            id: bg

            anchors.fill: parent
            radius: Tokens.rounding.large
            color: Colours.palette.m3surfaceContainerLow

            ColumnLayout {
                id: column

                anchors.fill: parent
                anchors.margins: Tokens.padding.extraSmall
                spacing: 0

                Repeater {
                    id: repeater

                    model: root.items

                    StyledRect {
                        id: item

                        required property int index
                        required property var modelData
                        readonly property bool active: index === root.activeIndex
                        readonly property bool first: index === 0
                        readonly property bool last: index === repeater.count - 1

                        Layout.fillWidth: true
                        implicitWidth: row.implicitWidth + Tokens.padding.medium * 2
                        implicitHeight: row.implicitHeight + Tokens.padding.medium * 2

                        radius: active ? Tokens.rounding.medium : Tokens.rounding.extraSmall
                        topLeftRadius: first ? Tokens.rounding.medium : radius
                        topRightRadius: first ? Tokens.rounding.medium : radius
                        bottomLeftRadius: last ? Tokens.rounding.medium : radius
                        bottomRightRadius: last ? Tokens.rounding.medium : radius

                        color: Qt.alpha(Colours.palette.m3tertiaryContainer, active ? 1 : 0)

                        Behavior on radius {
                            Anim {}
                        }

                        // The keyboard's place in the list, drawn as the
                        // pointer's hover is.
                        Rectangle {
                            anchors.fill: parent
                            topLeftRadius: item.topLeftRadius
                            topRightRadius: item.topRightRadius
                            bottomLeftRadius: item.bottomLeftRadius
                            bottomRightRadius: item.bottomRightRadius
                            color: item.active ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurface
                            opacity: item.index === root.keyIndex && !mouse.containsMouse ? 0.08 : 0

                            Behavior on opacity {
                                Anim {
                                    type: Anim.DefaultEffects
                                }
                            }
                        }

                        StateLayer {
                            id: mouse

                            radius: item.last || item.first ? Tokens.rounding.medium : item.radius
                            color: item.active ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurface
                            disabled: !root.expanded
                            onClicked: root.choose(item.index)
                        }

                        RowLayout {
                            id: row

                            anchors.fill: parent
                            anchors.margins: Tokens.padding.medium
                            spacing: Tokens.spacing.small

                            MaterialIcon {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.topMargin: 1
                                text: item.modelData.icon ?? ""
                                color: item.active ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurfaceVariant
                                size: Tokens.font.iconMedium
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.fillWidth: true
                                text: item.modelData.text ?? ""
                                elide: Text.ElideRight
                                color: item.active ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurface
                                font.pointSize: Tokens.font.bodyMedium
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.leftMargin: Tokens.spacing.small
                                visible: text !== ""
                                text: item.modelData.detail ?? ""
                                color: item.active ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurfaceVariant
                                font.pointSize: Tokens.font.bodySmall
                            }
                        }
                    }
                }
            }
        }
    }
}
