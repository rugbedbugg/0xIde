pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components.controls
import qs.services

// Laid over a wallpaper preview on right-click: the image's size in pixels,
// on disk and in memory, and a button that moves it to the Trash after a
// confirming second click. Clicking anywhere else on it closes it.
Item {
    id: root

    required property string path
    // On disk, in bytes; -1 when unknown.
    property real fileSize: -1
    // Corner rounding, when it is not inside a clipping rectangle already.
    property real radius

    readonly property bool open: path !== "" && WallpaperInfo.openPath === path
    readonly property bool known: open && WallpaperInfo.width > 0
    readonly property bool inUse: path === Wallpapers.actualCurrent
    property bool confirming

    visible: opacity > 0
    opacity: open ? 1 : 0
    onOpenChanged: confirming = false

    Component.onDestruction: {
        if (open)
            WallpaperInfo.hide();
    }

    Behavior on opacity {
        Anim {
            type: Anim.DefaultEffects
        }
    }

    StyledRect {
        anchors.fill: parent
        radius: root.radius
        color: Qt.alpha(Colours.palette.m3scrim, 0.72)
    }

    // Takes every click on the preview while open, so a left click cannot
    // also pick this wallpaper.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: WallpaperInfo.hide()
        onWheel: wheel => wheel.accepted = true
    }

    ColumnLayout {
        anchors.centerIn: parent
        width: Math.min(implicitWidth, parent.width - Tokens.padding.medium * 2)
        spacing: Tokens.spacing.extraSmall

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            color: "white"
            font: Tokens.font.label.large
            text: {
                if (root.known)
                    return qsTr("%1 × %2 px").arg(WallpaperInfo.width).arg(WallpaperInfo.height);
                return WallpaperInfo.error ? qsTr("Size unknown") : qsTr("Reading…");
            }
        }

        StyledText {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
            color: Qt.alpha("white", 0.8)
            font: Tokens.font.label.small
            text: {
                const parts = [];
                if (root.fileSize >= 0)
                    parts.push(qsTr("%1 file").arg(WallpaperInfo.formatBytes(root.fileSize)));
                if (root.known)
                    parts.push(qsTr("%1 in memory").arg(WallpaperInfo.formatBytes(WallpaperInfo.width * WallpaperInfo.height * 4)));
                return parts.join(" · ");
            }
        }

        StyledText {
            Layout.fillWidth: true
            visible: text !== ""
            horizontalAlignment: Text.AlignHCenter
            // The reason a delete failed is the point: wrapped, not cut off.
            wrapMode: Text.Wrap
            maximumLineCount: 4
            elide: Text.ElideRight
            color: Colours.palette.m3error
            font: Tokens.font.label.small
            text: root.open ? WallpaperInfo.trashError : ""
        }

        IconTextButton {
            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Tokens.spacing.extraSmall
            icon: root.confirming ? "delete_forever" : "delete"
            text: {
                if (root.inUse)
                    return qsTr("In use");
                if (WallpaperInfo.trashing)
                    return qsTr("Moving…");
                return root.confirming ? qsTr("Move to Trash?") : qsTr("Delete");
            }
            font: Tokens.font.label.medium
            isRound: true
            horizontalPadding: Tokens.padding.medium
            verticalPadding: Tokens.padding.small
            disabled: root.inUse || WallpaperInfo.trashing
            inactiveColour: root.confirming ? Colours.palette.m3error : Colours.palette.m3errorContainer
            inactiveOnColour: root.confirming ? Colours.palette.m3onError : Colours.palette.m3onErrorContainer
            onClicked: {
                if (root.confirming)
                    WallpaperInfo.trash();
                else
                    root.confirming = true;
            }
        }
    }
}
