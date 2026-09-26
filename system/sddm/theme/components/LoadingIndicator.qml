import QtQuick

// Material 3 expressive loading indicator: the shell's spring-driven shape
// morph when M3Shapes is installed, a rotating, pulsing shape without it.
Item {
    id: root

    property real implicitSize: 38
    property color color: Colours.palette.m3primary

    implicitWidth: implicitSize
    implicitHeight: implicitSize

    Loader {
        id: loader

        anchors.centerIn: parent
        width: root.implicitSize
        height: root.implicitSize
        source: "LoadingIndicatorM3.qml"
        onStatusChanged: {
            if (status === Loader.Error)
                sourceComponent = fallback;
        }
    }

    Binding {
        target: loader.item
        property: "color"
        value: root.color
        when: loader.status === Loader.Ready
    }

    Component {
        id: fallback

        ShapeFallback {
            id: spinner

            shapeName: "Square"
            antialiasing: true

            RotationAnimation on rotation {
                from: 0
                to: 360
                duration: 1400
                loops: Animation.Infinite
            }

            SequentialAnimation on scale {
                loops: Animation.Infinite

                Anim {
                    from: 0.8
                    to: 1
                    type: Anim.SlowSpatial
                }
                Anim {
                    from: 1
                    to: 0.8
                    type: Anim.SlowSpatial
                }
            }
        }
    }
}
