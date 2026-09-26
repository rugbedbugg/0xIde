pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import "../components"

// The account's picture in a circle on surfaceContainerHigh, with the person
// symbol while there is none, as the shell draws avatars outside the lock.
//
// The lockscreen reads ~/.face; the greeter cannot, because home directories
// are private. system/sddm/sync hands the helper the same file, which installs
// it as faces/<user> in this theme. SDDM's own lookup is the fallback.
Item {
    id: root

    property string userName
    property string modelIcon
    property color colour: Colours.palette.m3surfaceContainerHigh
    property color onColour: Colours.palette.m3onSurfaceVariant

    // A different user starts the lookup over.
    onUserNameChanged: pfp.attempt = 0

    Rectangle {
        id: circle

        anchors.fill: parent
        radius: width / 2
        color: root.colour
        layer.enabled: true

        Behavior on color {
            CAnim {}
        }
    }

    MaterialIcon {
        anchors.centerIn: parent
        anchors.verticalCenterOffset: 1
        text: "person"
        color: root.onColour
        size: Math.round(root.width * 0.45)
        visible: pfp.status !== Image.Ready
    }

    Image {
        id: pfp

        property int attempt

        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        sourceSize.width: width * 2
        sourceSize.height: height * 2
        source: {
            if (!root.userName)
                return "";
            if (attempt === 0)
                return Qt.resolvedUrl("../faces/" + root.userName);
            // SDDM's generic face, which it gives every account it cannot
            // read a picture for, is not a picture of anyone: the symbol is.
            const generic = /\/sddm\/faces\/\.face\.icon$/.test(String(root.modelIcon));
            return attempt === 1 && !generic ? root.modelIcon : "";
        }
        onStatusChanged: {
            if (status === Image.Error)
                attempt++;
        }

        visible: false
    }

    MultiEffect {
        anchors.fill: parent
        source: pfp
        visible: pfp.status === Image.Ready
        maskEnabled: true
        maskSource: circle
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1
    }
}
