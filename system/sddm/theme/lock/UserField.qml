pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import "../components"

// Who is logging in: the account's picture, then its user name in a text
// field over an underline, as the shell's text fields draw theirs (a primary
// cursor and a primary-tinted selection). Any name can be typed; the chevron
// opens the accounts SDDM knows, to pick one instead. The line thickens into
// primary while the field has the keyboard or the menu is open.
//
// It is an M3 filled text field: rounded at the top, square where the line
// runs. The fill is frosted, the wallpaper behind the field blurred and
// tinted with the password pill's surface, so the name reads on any wallpaper
// while the wallpaper still shows through.
Item {
    id: root

    required property real scaleFactor
    // The account the typed name belongs to, for its picture; empty for a
    // name SDDM does not list.
    property string knownUser
    property string modelIcon
    property bool expandable
    property bool expanded
    property alias text: input.text
    readonly property bool lit: expanded || input.activeFocus
    // What to frost: the wallpaper, filling the screen from its top left.
    property Item frostSource
    // Anything that moves the field on screen, so the frost follows it;
    // mapToItem() is not a binding that updates by itself.
    property real track

    // Typing, as opposed to text set from outside.
    signal edited(string name)
    signal accepted
    signal menuRequested

    function focusInput(): void {
        input.forceActiveFocus();
        input.selectAll();
    }

    implicitHeight: row.implicitHeight + Tokens.padding.small * 2

    Item {
        id: frost

        // Blurring only the field's own patch would pull transparency in at
        // its edges, so the patch reaches past them and is cut back after.
        readonly property int reach: 48

        anchors.fill: parent
        visible: root.frostSource !== null

        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: frostMask
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1
        }

        ShaderEffectSource {
            id: patch

            x: -frost.reach
            y: -frost.reach
            width: root.width + frost.reach * 2
            height: root.height + frost.reach * 2
            visible: false

            sourceItem: root.frostSource
            sourceRect: {
                root.track;
                root.width;
                root.height;
                if (!root.frostSource)
                    return Qt.rect(0, 0, 0, 0);
                const p = root.mapToItem(root.frostSource, 0, 0);
                return Qt.rect(p.x - frost.reach, p.y - frost.reach, width, height);
            }
        }

        MultiEffect {
            anchors.fill: patch
            source: patch
            autoPaddingEnabled: false
            blurEnabled: true
            blur: 1
            blurMax: 48
            blurMultiplier: 1
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(Colours.palette.m3surfaceContainer, 0.55)

            Behavior on color {
                CAnim {}
            }
        }
    }

    Rectangle {
        id: frostMask

        anchors.fill: parent
        topLeftRadius: Tokens.rounding.medium
        topRightRadius: Tokens.rounding.medium
        visible: false
        layer.enabled: true
    }

    RowLayout {
        id: row

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Tokens.padding.small
        anchors.rightMargin: Tokens.padding.small
        anchors.verticalCenter: parent.verticalCenter
        spacing: Tokens.spacing.large

        Avatar {
            Layout.preferredWidth: Math.round(40 * root.scaleFactor)
            Layout.preferredHeight: Math.round(40 * root.scaleFactor)
            userName: root.knownUser
            modelIcon: root.modelIcon
            colour: root.lit ? Colours.palette.m3primaryContainer : Colours.palette.m3surfaceContainerHigh
            onColour: root.lit ? Colours.palette.m3onPrimaryContainer : Colours.palette.m3onSurfaceVariant
        }

        Item {
            Layout.fillWidth: true
            implicitHeight: input.implicitHeight

            TextInput {
                id: input

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter

                color: Colours.palette.m3onSurface
                selectionColor: Qt.alpha(Colours.palette.m3primary, 0.4)
                selectedTextColor: color
                font.family: Tokens.font.sans
                font.pointSize: Tokens.font.labelLarge * root.scaleFactor
                font.weight: Font.DemiBold
                font.variableAxes: ({ "ROND": 25 })
                clip: true
                selectByMouse: true
                activeFocusOnTab: true
                // What a login name can hold, including directory accounts'
                // user@domain; never a path separator.
                validator: RegularExpressionValidator {
                    regularExpression: /[A-Za-z0-9._@-]{0,64}/
                }

                cursorDelegate: StyledRect {
                    implicitWidth: 1.5
                    color: Colours.palette.m3primary
                    radius: Tokens.rounding.large
                    visible: input.activeFocus

                    SequentialAnimation on opacity {
                        running: input.activeFocus
                        loops: Animation.Infinite

                        PropertyAction {
                            value: 1
                        }
                        PauseAnimation {
                            duration: 500
                        }
                        PropertyAction {
                            value: 0
                        }
                        PauseAnimation {
                            duration: 500
                        }
                    }
                }

                onTextEdited: root.edited(text)
                onAccepted: root.accepted()
                Keys.onDownPressed: root.menuRequested()

                Behavior on color {
                    CAnim {}
                }
            }

            StyledText {
                anchors.verticalCenter: parent.verticalCenter
                visible: !input.text
                text: qsTr("Username")
                color: Colours.palette.m3outline
                font: input.font
            }

            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.NoButton
                cursorShape: Qt.IBeamCursor
            }
        }

        StyledRect {
            id: chevron

            Layout.rightMargin: Tokens.padding.extraSmall
            implicitWidth: implicitHeight
            implicitHeight: {
                const h = chevronIcon.implicitHeight + Tokens.padding.extraSmall * 2;
                return h % 2 === 0 ? h : h + 1;
            }
            visible: root.expandable
            radius: height / 2
            color: root.expanded ? Colours.palette.m3secondaryContainer : "transparent"

            StateLayer {
                color: root.expanded ? Colours.palette.m3onSecondaryContainer : Colours.palette.m3onSurfaceVariant
                onClicked: root.menuRequested()
            }

            MaterialIcon {
                id: chevronIcon

                anchors.centerIn: parent
                anchors.verticalCenterOffset: 1
                text: "expand_more"
                color: root.expanded ? Colours.palette.m3onSecondaryContainer : root.lit ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant
                size: Tokens.font.iconMedium * root.scaleFactor
                rotation: root.expanded ? 180 : 0

                Behavior on rotation {
                    Anim {}
                }
            }
        }
    }

    StyledRect {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom

        implicitHeight: root.lit ? 2 : 1
        radius: height / 2
        color: root.lit ? Colours.palette.m3primary : Colours.palette.m3onSurfaceVariant

        Behavior on implicitHeight {
            Anim {
                type: Anim.FastSpatial
            }
        }
    }
}
