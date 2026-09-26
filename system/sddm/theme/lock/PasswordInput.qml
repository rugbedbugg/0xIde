pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../components"

// modules/lock/center/PasswordInput.qml: a full-round pill, only as wide as
// its placeholder until there is something typed, then out to a fixed full
// width. The lock symbol gives way to the loading indicator while SDDM checks
// the password; the enter button is a circle until there is something to
// submit, then morphs into a primary arrow.
//
// The lockscreen's full width is 80% of its centre column; here it is the
// account field's, so the two line up while you type.
StyledRect {
    id: root

    required property real centerScale
    required property Auth auth
    required property real fullWidth

    implicitWidth: auth.buffer ? fullWidth : Math.min(fullWidth, inputField.placeholderWidth + iconWrapper.implicitWidth + enterButton.implicitWidth + input.spacing * 2 + Tokens.padding.medium * 2)
    implicitHeight: input.implicitHeight + Tokens.padding.small

    color: Colours.surface(Colours.palette.m3surfaceContainer, "password")
    radius: height / 2

    focus: true
    activeFocusOnTab: true

    Keys.onPressed: event => {
        // Tab moves between this and the account field.
        if (event.key === Qt.Key_Tab || event.key === Qt.Key_Backtab) {
            event.accepted = false;
            return;
        }
        if (event.key === Qt.Key_Enter || event.key === Qt.Key_Return)
            inputField.placeholder.animate = false;

        root.auth.handleKey(event);
        event.accepted = true;
    }

    Behavior on implicitWidth {
        Anim {}
    }

    // Hyprland's blur behind a translucent surface; see Frost.
    Frost {
        anchors.fill: parent
        z: -1
        surface: "password"
        radius: root.radius
    }

    StateLayer {
        cursorShape: Qt.IBeamCursor
        color: "transparent"
        onClicked: root.forceActiveFocus()
    }

    RowLayout {
        id: input

        anchors.fill: parent
        anchors.margins: Tokens.padding.extraSmall
        spacing: Tokens.spacing.medium

        Item {
            id: iconWrapper

            Layout.fillHeight: true
            implicitWidth: height

            MaterialIcon {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 1
                text: "lock"
                color: Colours.palette.m3onSurfaceVariant
                size: Tokens.font.iconMedium * root.centerScale
                opacity: root.auth.active ? 0 : 1
                scale: root.auth.active ? 0.7 : 1

                Behavior on opacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
                Behavior on scale {
                    Anim {
                        type: Anim.FastSpatial
                    }
                }
            }

            LoadingIndicator {
                anchors.centerIn: parent
                implicitSize: iconWrapper.height - Tokens.padding.small * 2
                visible: opacity > 0
                opacity: root.auth.active ? 1 : 0
                scale: root.auth.active ? 1 : 0.7

                Behavior on opacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
                Behavior on scale {
                    Anim {
                        type: Anim.FastSpatial
                    }
                }
            }
        }

        InputField {
            id: inputField

            Layout.fillWidth: true
            Layout.fillHeight: true

            centerScale: root.centerScale
            auth: root.auth
        }

        Item {
            id: enterButton

            implicitWidth: implicitHeight
            implicitHeight: {
                const h = enterIcon.implicitHeight + Tokens.padding.extraSmall * 2;
                return h % 2 === 0 ? h : h + 1;
            }

            Shape {
                id: enterShape

                anchors.fill: parent

                color: root.auth.buffer ? Colours.palette.m3primary : Colours.surface(Colours.palette.m3surfaceContainerHigh, "password", 2)
                shape: root.auth.buffer ? "Arrow" : "Circle"
                scale: !root.auth.buffer ? 1 : mouse.pressed ? 0.6 : mouse.containsMouse ? 0.8 : 0.7
                rotation: 90

                Behavior on scale {
                    Anim {
                        type: Anim.FastSpatial
                    }
                }

                Behavior on color {
                    CAnim {}
                }

                MouseArea {
                    id: mouse

                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: root.auth.buffer ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: root.auth.submit()
                }
            }

            MaterialIcon {
                id: enterIcon

                anchors.centerIn: parent
                text: "arrow_forward"
                color: root.auth.buffer ? Colours.palette.m3onPrimary : Colours.palette.m3onSurfaceVariant
                size: Tokens.font.iconMedium * root.centerScale * 1.2
                // With M3Shapes the button itself becomes the arrow; the
                // fallback square cannot, so the symbol stays to say so.
                opacity: root.auth.buffer && enterShape.morphing ? 0 : 1

                Behavior on opacity {
                    Anim {
                        type: Anim.DefaultEffects
                    }
                }
            }
        }
    }
}
