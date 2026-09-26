pragma ComponentBehavior: Bound

import QtQuick
import "../components"

// modules/lock/center/StateMessage.qml: errors in m3error, which scale in and
// flash twice (and flash again when the same error repeats), and caps lock,
// num lock and keyboard layout state in onSurfaceVariant when there is no
// error. Lock-key state comes from SDDM's keyboard model instead of Hyprland.
Item {
    id: root

    required property Auth auth

    readonly property string layoutName: {
        const layouts = keyboard?.layouts ?? [];
        return layouts.length > 1 ? (layouts[keyboard.currentLayout]?.longName ?? "") : "";
    }

    readonly property string msg: {
        if (auth.infoMessage)
            return auth.infoMessage;
        if (auth.state === Auth.Failed)
            return qsTr("Incorrect password. Please try again.");
        return "";
    }

    readonly property string stateMsg: {
        const caps = keyboard?.capsLock ?? false;
        const num = keyboard?.numLock ?? false;
        if (layoutName) {
            if (caps && num)
                return qsTr("Caps lock and Num lock are ON.\nKeyboard layout: %1").arg(layoutName);
            if (caps)
                return qsTr("Caps lock is ON. Kb layout: %1").arg(layoutName);
            if (num)
                return qsTr("Num lock is ON. Kb layout: %1").arg(layoutName);
            return qsTr("Keyboard layout: %1").arg(layoutName);
        }

        if (caps && num)
            return qsTr("Caps lock and Num lock are ON.");
        if (caps)
            return qsTr("Caps lock is ON.");
        if (num)
            return qsTr("Num lock is ON.");
        return "";
    }

    property bool stateMsgShouldBeVisible

    function showMsg(): void {
        exitAnim.stop();
        if (message.scale < 1)
            appearAnim.restart();
        else
            flashAnim.restart();
    }

    onMsgChanged: {
        if (msg) {
            if (message.opacity > 0) {
                message.animate = true;
                message.text = msg;
                message.animate = false;
            } else {
                message.text = msg;
            }
            showMsg();
        } else {
            appearAnim.stop();
            flashAnim.stop();
            exitAnim.start();
        }
    }

    onStateMsgChanged: {
        if (stateMsg) {
            if (stateMessage.opacity > 0) {
                stateMessage.animate = true;
                stateMessage.text = stateMsg;
                stateMessage.animate = false;
            } else {
                stateMessage.text = stateMsg;
            }
            stateMsgShouldBeVisible = true;
        } else {
            stateMsgShouldBeVisible = false;
        }
    }

    Component.onCompleted: {
        if (stateMsg) {
            stateMessage.text = stateMsg;
            stateMsgShouldBeVisible = true;
        }
    }

    implicitHeight: Math.max(message.implicitHeight, stateMessage.implicitHeight) + Tokens.padding.small * 2

    Behavior on implicitHeight {
        Anim {}
    }

    // The lockscreen's messages sit on its panel; here they would sit on the
    // wallpaper, so they get a chip of the same surface to keep them legible.
    StyledRect {
        readonly property Text shown: root.msg ? message : stateMessage

        anchors.horizontalCenter: parent.horizontalCenter
        implicitWidth: Math.min(root.width, shown.contentWidth + Tokens.padding.large * 2)
        implicitHeight: shown.contentHeight + Tokens.padding.small * 2
        radius: Math.min(height / 2, Tokens.rounding.large)
        color: Colours.palette.m3surfaceContainer
        opacity: root.msg || root.stateMsgShouldBeVisible ? 1 : 0
        scale: root.msg || root.stateMsgShouldBeVisible ? 1 : 0.7

        Behavior on implicitWidth {
            Anim {}
        }
        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
        Behavior on scale {
            Anim {}
        }
    }

    StyledText {
        id: stateMessage

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Tokens.padding.large
        anchors.rightMargin: Tokens.padding.large
        y: Tokens.padding.small

        scale: root.stateMsgShouldBeVisible && !root.msg ? 1 : 0.7
        opacity: root.stateMsgShouldBeVisible && !root.msg ? 1 : 0
        color: Colours.palette.m3onSurfaceVariant

        horizontalAlignment: Qt.AlignHCenter
        wrapMode: Text.WrapAtWordBoundaryOrAnywhere
        lineHeight: 1.2

        Behavior on scale {
            Anim {}
        }

        Behavior on opacity {
            Anim {
                type: Anim.DefaultEffects
            }
        }
    }

    StyledText {
        id: message

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: Tokens.padding.large
        anchors.rightMargin: Tokens.padding.large
        y: Tokens.padding.small

        scale: 0.7
        opacity: 0
        color: Colours.palette.m3error

        horizontalAlignment: Qt.AlignHCenter
        wrapMode: Text.WrapAtWordBoundaryOrAnywhere

        Connections {
            function onFlashMsg(): void {
                root.showMsg();
            }

            target: root.auth
        }

        Anim {
            id: appearAnim

            type: Anim.DefaultEffects
            target: message
            properties: "scale,opacity"
            to: 1
            onFinished: flashAnim.restart()
        }

        SequentialAnimation {
            id: flashAnim

            loops: 2

            FlashAnim {
                to: 0.3
            }
            FlashAnim {
                to: 1
            }
        }

        ParallelAnimation {
            id: exitAnim

            Anim {
                target: message
                property: "scale"
                to: 0.7
                type: Anim.StandardLarge
            }
            Anim {
                target: message
                property: "opacity"
                to: 0
                type: Anim.StandardLarge
            }
        }
    }

    component FlashAnim: NumberAnimation {
        target: message
        property: "opacity"
        duration: Tokens.anim.durations.small
        easing.type: Easing.Linear
    }
}
