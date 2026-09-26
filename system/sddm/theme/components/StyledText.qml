import QtQuick

// With animate set, a text change fades out, swaps, and fades back in.
Text {
    id: root

    property bool animate: false

    renderType: Text.NativeRendering
    textFormat: Text.PlainText
    color: Colours.palette.m3onSurface
    font.family: Tokens.font.sans
    font.pointSize: Tokens.font.bodySmall
    font.variableAxes: ({ "ROND": 25 })

    Behavior on color {
        CAnim {}
    }

    Behavior on text {
        enabled: root.animate

        SequentialAnimation {
            Anim {
                target: root
                property: "opacity"
                to: 0
                type: Anim.FastEffects
            }
            PropertyAction {}
            Anim {
                target: root
                property: "opacity"
                to: 1
                type: Anim.DefaultEffects
            }
        }
    }
}
