import QtQuick
import QtQuick.Layouts
import "../components"

// modules/lock/Center.qml. A greeter also has to say whose password it wants,
// so the account's name sits under the picture, where the lockscreen needs
// none.
ColumnLayout {
    id: root

    required property Auth auth
    required property real screenHeight
    property string realName
    property string modelIcon
    property bool twelveHour

    readonly property real centerScale: Math.min(1, screenHeight / 1440)
    readonly property int centerWidth: Tokens.lock.centerWidth * centerScale

    Layout.preferredWidth: centerWidth
    Layout.fillWidth: false
    Layout.fillHeight: true

    spacing: Tokens.spacing.largeIncreased

    Clock {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Tokens.padding.large
        centerScale: root.centerScale
        twelveHour: root.twelveHour
    }

    StyledText {
        id: date

        property date now: new Date()

        Layout.alignment: Qt.AlignHCenter

        text: Qt.formatDate(now, "dddd • d MMM").toUpperCase()
        color: Colours.palette.m3onSurface
        font.pointSize: Tokens.font.titleMedium
        font.weight: Font.DemiBold

        Timer {
            interval: 60000
            running: true
            repeat: true
            onTriggered: date.now = new Date()
        }
    }

    ProfilePic {
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: Tokens.spacing.extraExtraLarge * root.centerScale
        centerWidth: root.centerWidth
        userName: root.auth.user
        modelIcon: root.modelIcon
    }

    StyledText {
        Layout.alignment: Qt.AlignHCenter
        Layout.bottomMargin: Tokens.spacing.large * root.centerScale

        animate: true
        text: root.realName || root.auth.user
        color: Colours.palette.m3onSurfaceVariant
        font.pointSize: Tokens.font.titleMedium
        font.weight: Font.Medium
    }

    PasswordInput {
        id: input

        Layout.alignment: Qt.AlignHCenter
        centerScale: Math.max(0.8, root.centerScale)
        centerWidth: root.centerWidth
        auth: root.auth
    }

    StateMessage {
        Layout.fillWidth: true
        auth: root.auth
    }

    function focusInput(): void {
        input.forceActiveFocus();
    }
}
