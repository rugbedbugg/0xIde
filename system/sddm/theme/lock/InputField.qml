pragma ComponentBehavior: Bound

import QtQuick
import "../components"

// modules/lock/center/InputField.qml. Each character arrives as one of
// Material 3's expressive shapes, in a shuffled order, then settles into a
// circle; a removed one fades and shrinks away. Quickshell's ScriptModel is
// not available here, so a ListModel is kept in step with the buffer instead,
// which gives the same per-character add and remove animations.
Item {
    id: root

    required property real centerScale
    required property Auth auth
    readonly property alias placeholder: placeholder
    readonly property alias placeholderWidth: nonAnimPlaceholder.width
    property string buffer
    readonly property var shapeQueue: {
        const shapes = ["Slanted", "Arch", "Fan", "Arrow", "SemiCircle", "Triangle", "Diamond", "ClamShell", "Pentagon", "Gem", "Sunny", "VerySunny", "Cookie4Sided", "Ghostish", "SoftBurst"];
        for (let i = shapes.length - 1; i > 0; i--) {
            const j = Math.floor(Math.random() * (i + 1));
            [shapes[i], shapes[j]] = [shapes[j], shapes[i]];
        }
        return shapes;
    }

    clip: true

    ListModel {
        id: chars
    }

    Connections {
        function onBufferChanged(): void {
            const next = root.auth.buffer;
            if (next.length > root.buffer.length) {
                charList.bindImWidth();
            } else if (next.length === 0) {
                charList.implicitWidth = charList.implicitWidth;
                placeholder.animate = true;
            }

            while (chars.count > next.length)
                chars.remove(chars.count - 1);
            while (chars.count < next.length)
                chars.append({});

            root.buffer = next;
        }

        target: root.auth
    }

    TextMetrics {
        id: nonAnimPlaceholder

        text: root.auth.active ? qsTr("Loading...") : qsTr("Enter your password")
        font: placeholder.font
    }

    // Hidden while there is input. The fade sits on a wrapper because the
    // text's own change animation also drives opacity, and would otherwise
    // replace this binding and leave the placeholder over the characters.
    Item {
        anchors.fill: parent
        opacity: root.buffer ? 0 : 1

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }

        StyledText {
            id: placeholder

            anchors.centerIn: parent
            anchors.verticalCenterOffset: 1

            text: nonAnimPlaceholder.text

            animate: true
            color: root.auth.active ? Colours.palette.m3secondary : Colours.palette.m3outline
            font.pointSize: Tokens.font.bodyMedium * root.centerScale
            font.variableAxes: ({ "ROND": 25, "wdth": 110 })
        }
    }

    ListView {
        id: charList

        readonly property int fullWidth: {
            let w = (count - 1) * spacing;
            for (let i = 0; i < count; i++)
                w += (itemAtIndex(i)?.nonAnimWidthScale ?? 1) * implicitHeight;
            return w + implicitHeight; // Extra padding at ends
        }

        function bindImWidth(): void {
            imWidthBehavior.enabled = false;
            implicitWidth = Qt.binding(() => fullWidth);
            imWidthBehavior.enabled = true;
        }

        anchors.centerIn: parent
        anchors.horizontalCenterOffset: implicitWidth > root.width ? -(implicitWidth - root.width) / 2 : 0

        implicitWidth: fullWidth
        implicitHeight: Tokens.font.bodyMedium

        orientation: Qt.Horizontal
        spacing: Tokens.spacing.extraSmall
        interactive: false

        model: chars
        delegate: CharItem {}

        Behavior on implicitWidth {
            id: imWidthBehavior

            Anim {}
        }
    }

    component CharItem: Item {
        id: char

        required property int index
        property real nonAnimWidthScale: 1

        implicitHeight: charList.implicitHeight

        ListView.onRemove: {
            initAnim.stop();
            removeAnim.start();
        }

        Shape {
            id: charShape

            anchors.centerIn: parent
            implicitSize: charList.implicitHeight * 1.5
            shape: root.shapeQueue[char.index % root.shapeQueue.length] ?? "Circle"
            color: Colours.palette.m3onSurface

            Behavior on color {
                CAnim {}
            }

            SequentialAnimation {
                id: initAnim

                running: true

                ParallelAnimation {
                    Anim {
                        target: charShape
                        property: "opacity"
                        from: 0
                        to: 1
                        type: Anim.DefaultEffects
                    }
                    Anim {
                        target: charShape
                        property: "scale"
                        from: 0
                        to: 1
                        type: Anim.FastSpatial
                    }
                    Anim {
                        target: char
                        property: "implicitWidth"
                        from: charList.implicitHeight
                        to: charList.implicitHeight * 1.3
                        type: Anim.DefaultEffects
                    }
                    PropertyAction {
                        target: char
                        property: "nonAnimWidthScale"
                        value: 1.5
                    }
                }
                PauseAnimation {
                    duration: 180
                }
                PropertyAction {
                    target: charShape
                    property: "shape"
                    value: "Circle"
                }
                ParallelAnimation {
                    Anim {
                        target: charShape
                        property: "scale"
                        to: 2 / 3
                        type: Anim.FastSpatial
                    }
                    Anim {
                        target: char
                        property: "implicitWidth"
                        to: charList.implicitHeight
                        type: Anim.DefaultEffects
                    }
                    PropertyAction {
                        target: char
                        property: "nonAnimWidthScale"
                        value: 1
                    }
                }
            }

            SequentialAnimation {
                id: removeAnim

                PropertyAction {
                    target: char
                    property: "ListView.delayRemove"
                    value: true
                }
                ParallelAnimation {
                    Anim {
                        type: Anim.DefaultEffects
                        target: charShape
                        property: "opacity"
                        to: 0
                    }
                    Anim {
                        target: charShape
                        property: "scale"
                        to: 0.5
                    }
                }
                PropertyAction {
                    target: char
                    property: "ListView.delayRemove"
                    value: false
                }
            }
        }
    }
}
