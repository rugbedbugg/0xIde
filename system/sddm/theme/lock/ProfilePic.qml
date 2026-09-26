pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import "../components"

// modules/lock/center/ProfilePic.qml: the avatar masked into a ClamShell, on
// surfaceContainerHighest, with the person symbol when there is no picture.
//
// The lockscreen reads ~/.face; the greeter cannot, because home directories
// are private. system/sddm/sync hands the helper the same file, which installs
// it as faces/<user> in this theme. SDDM's own lookup is the fallback.
Item {
    id: root

    required property int centerWidth
    property string userName
    property string modelIcon

    implicitWidth: Math.round(centerWidth * 0.7)
    implicitHeight: shape.morphing ? shape.item.pathBounds().height : implicitWidth

    Shape {
        id: shape

        anchors.centerIn: parent
        width: root.implicitWidth
        height: root.implicitWidth
        shape: "ClamShell"
        color: Colours.palette.m3surfaceContainerHighest
        layer.enabled: true
    }

    MaterialIcon {
        anchors.centerIn: parent
        text: "person"
        color: Colours.palette.m3onSurfaceVariant
        size: root.centerWidth / 4
        visible: pfp.status !== Image.Ready
    }

    Image {
        id: pfp

        property int attempt

        anchors.fill: shape
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        sourceSize.width: width
        sourceSize.height: height
        source: {
            if (!root.userName)
                return "";
            if (attempt === 0)
                return Qt.resolvedUrl("../faces/" + root.userName);
            return attempt === 1 ? root.modelIcon : "";
        }
        onStatusChanged: {
            if (status === Image.Error)
                attempt++;
        }

        visible: false
    }

    MultiEffect {
        anchors.fill: shape
        source: pfp
        visible: pfp.status === Image.Ready
        maskEnabled: true
        maskSource: shape
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1
    }

    // A different user starts the lookup over.
    onUserNameChanged: pfp.attempt = 0
}
