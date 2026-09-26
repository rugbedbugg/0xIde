import QtQuick

// A Material 3 expressive shape, by name ("Circle", "Arrow", "ClamShell", ...).
//
// The real morphing shapes come from M3Shapes, the module the Caelestia shell
// itself uses, and are loaded when it is installed. Without it the theme still
// works: a rounded square stands in, animating its corners between a circle
// and a soft square so a change of shape still reads as one.
Item {
    id: root

    property string shape: "Circle"
    property color color: Colours.palette.m3primary
    property real implicitSize: 24
    readonly property bool morphing: loader.source.toString().endsWith("ShapeM3.qml") && loader.status === Loader.Ready
    readonly property Item item: loader.item

    implicitWidth: implicitSize
    implicitHeight: implicitSize

    Loader {
        id: loader

        anchors.fill: parent
        source: "ShapeM3.qml"
        onStatusChanged: {
            if (status === Loader.Error)
                source = "ShapeFallback.qml";
        }
    }

    Binding {
        target: loader.item
        property: "shapeName"
        value: root.shape
        when: loader.status === Loader.Ready
    }

    Binding {
        target: loader.item
        property: "color"
        value: root.color
        when: loader.status === Loader.Ready
    }
}
