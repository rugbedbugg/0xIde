pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import "../components"

// components/controls/Menu.qml from the shell: a surfaceContainerLow card at
// elevation 2 that unfolds from the edge it is attached to, at least 200 wide
// and lined up with its right edge; rows of a small symbol and body-small text
// whose corners round off at the ends of the list; and the chosen row on
// tertiaryContainer with the tighter medium rounding. It fills the screen
// while open, so a click anywhere else closes it.
//
// Added for the greeter: a row can show an account's picture in place of the
// symbol, a second, quieter label, and M3's disabled state for what cannot be
// done now. The shell's menus are only for the pointer; here the password
// field keeps the keyboard, so Main hands the arrow keys, Enter and Escape to
// whichever menu is open.
MouseArea {
    id: root

    required property Item attachTo
    // Unfold upwards from the top edge of attachTo, instead of down from its
    // bottom edge.
    property bool above
    // Line up with attachTo's left edge instead of its right, for a menu
    // attached near the left of the screen.
    property bool alignLeft
    property real minWidth: 200
    // [{ icon, text, detail, user, disabled }]
    property var items: []
    property int activeIndex: -1
    property int keyIndex: -1
    property bool expanded

    signal selected(int index)

    function open(): void {
        const p = attachTo.mapToItem(root, 0, 0);
        const x = alignLeft ? p.x : p.x + attachTo.width - menu.width;
        menu.x = Math.max(Tokens.padding.large, Math.min(x, root.width - menu.width - Tokens.padding.large));
        menu.y = above ? p.y - menu.height - Tokens.spacing.small : p.y + attachTo.height + Tokens.spacing.small;
        keyIndex = activeIndex;
        expanded = true;
    }

    // The next row that can be chosen, either way round, skipping disabled
    // ones.
    function move(delta: int): void {
        const n = items.length;
        let i = keyIndex < 0 ? (delta > 0 ? -1 : 0) : keyIndex;
        for (let step = 0; step < n; step++) {
            i = (i + delta + n) % n;
            if (!items[i].disabled) {
                keyIndex = i;
                return;
            }
        }
    }

    function choose(index: int): void {
        if (index < 0 || index >= items.length || items[index].disabled)
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
                        readonly property bool disabled: modelData.disabled ?? false
                        readonly property color onColour: disabled ? Qt.alpha(Colours.palette.m3onSurface, 0.38) : active ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurface
                        readonly property color onVariantColour: disabled ? onColour : active ? Colours.palette.m3onTertiaryContainer : Colours.palette.m3onSurfaceVariant

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
                            color: item.onColour
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
                            color: item.onColour
                            disabled: !root.expanded || item.disabled
                            onClicked: root.choose(item.index)
                        }

                        RowLayout {
                            id: row

                            anchors.fill: parent
                            anchors.margins: Tokens.padding.medium
                            spacing: Tokens.spacing.small

                            MaterialIcon {
                                id: icon

                                Layout.alignment: Qt.AlignVCenter
                                Layout.topMargin: 1
                                visible: !item.modelData.user
                                text: item.modelData.icon ?? ""
                                color: item.onVariantColour
                            }

                            Avatar {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: Math.round(icon.implicitHeight * 1.2)
                                Layout.preferredHeight: Math.round(icon.implicitHeight * 1.2)
                                visible: !!item.modelData.user
                                userName: item.modelData.user ?? ""
                                modelIcon: item.modelData.userIcon ?? ""
                                colour: item.active ? Colours.palette.m3tertiary : Colours.palette.m3surfaceContainerHighest
                                onColour: item.active ? Colours.palette.m3onTertiary : Colours.palette.m3onSurfaceVariant
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.fillWidth: true
                                text: item.modelData.text ?? ""
                                elide: Text.ElideRight
                                color: item.onColour
                            }

                            StyledText {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.leftMargin: Tokens.spacing.small
                                visible: text !== ""
                                text: item.modelData.detail ?? ""
                                color: item.onVariantColour
                            }
                        }
                    }
                }
            }
        }
    }
}
