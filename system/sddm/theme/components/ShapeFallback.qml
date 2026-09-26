import QtQuick

// Stands in for MaterialShape when M3Shapes is not installed.
Rectangle {
    property string shapeName: "Circle"

    anchors.fill: parent
    radius: shapeName === "Circle" || shapeName === "Oval" ? width / 2 : width * 0.3
    rotation: shapeName === "Diamond" || shapeName === "Gem" ? 45 : 0

    Behavior on radius {
        Anim {
            type: Anim.FastSpatial
        }
    }

    Behavior on rotation {
        Anim {
            type: Anim.FastSpatial
        }
    }
}
