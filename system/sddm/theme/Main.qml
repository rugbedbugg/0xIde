pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import QtQml.Models
import "components"
import "lock"

// A Caelestia login screen: the lockscreen's clock, date and password pill
// (modules/lock/center at the pinned shell revision) as one centred column
// over the wallpaper, with the account above the pill, and the power actions
// and the session to start behind two buttons in the bottom-left corner.
//
// SDDM creates this once per screen. The form is only on the primary one, so
// there is a single password field; the others show the wallpaper and clock.
Item {
    id: root

    readonly property bool primary: typeof primaryScreen === "undefined" || primaryScreen
    readonly property var cfg: typeof config === "undefined" ? ({}) : config
    readonly property alias unlocking: unlockAnim.running
    // For tests/run, which drives the login flow without a daemon.
    readonly property Auth auth: authState

    // Sizes are drawn for a 1080-pixel-high screen and follow the screen's
    // height from there, so the column keeps its proportions on any display.
    readonly property real scaleFactor: Math.max(0.75, height / 1080)
    readonly property int formWidth: Math.round(360 * scaleFactor)

    // The name in the account field: SDDM's last user to start with, then
    // whatever is typed or picked. It is what SDDM is asked to log in, listed
    // or not; userIndex is its row in SDDM's list, or -1.
    property string userName: userModel.lastUser ?? ""
    property int userIndex: -1
    property int sessionIndex: Math.max(0, sessionModel.lastIndex)

    width: 1920
    height: 1080

    Component.onCompleted: Colours.load(cfg)

    // Model rows as objects, so the chosen user and session can be read by
    // index; SDDM's models expose roles only to delegates. objectAt() is not
    // a binding that updates, so both are refreshed whenever a row arrives or
    // the choice changes.
    Instantiator {
        id: users

        model: userModel
        onObjectAdded: root.refresh()
        onObjectRemoved: root.refresh()
        delegate: QtObject {
            required property string name
            required property string realName
            required property string icon
            required property bool needsPassword
        }
    }

    Instantiator {
        id: sessions

        model: sessionModel
        onObjectAdded: root.refresh()
        onObjectRemoved: root.refresh()
        delegate: QtObject {
            required property string name
        }
    }

    property QtObject currentUser: null
    property string currentSession
    property var userItems: []
    property var sessionItems: []

    function refresh(): void {
        currentSession = sessions.objectAt(sessionIndex)?.name ?? "";

        const u = [];
        let found = -1;
        for (let i = 0; i < users.count; i++) {
            const o = users.objectAt(i);
            if (!o)
                continue;
            u.push({ icon: "person", text: o.realName || o.name, detail: o.realName && o.realName !== o.name ? o.name : "" });
            if (o.name === userName)
                found = i;
        }
        userItems = u;
        userIndex = found;
        currentUser = found < 0 ? null : users.objectAt(found);

        const s = [];
        for (let i = 0; i < sessions.count; i++) {
            const o = sessions.objectAt(i);
            if (o)
                s.push({ icon: "desktop_windows", text: o.name });
        }
        sessionItems = s;
    }

    onUserNameChanged: refresh()
    onSessionIndexChanged: refresh()

    // Only the actions SDDM says it can perform, with the session menu's
    // symbols (modules/session/Content.qml).
    readonly property var powerActions: {
        const a = [];
        if (sddm.canSuspend)
            a.push({ icon: "bedtime", text: qsTr("Suspend"), run: () => sddm.suspend() });
        if (sddm.canHibernate)
            a.push({ icon: "downloading", text: qsTr("Hibernate"), run: () => sddm.hibernate() });
        if (sddm.canReboot)
            a.push({ icon: "cached", text: qsTr("Reboot"), run: () => sddm.reboot() });
        if (sddm.canPowerOff)
            a.push({ icon: "power_settings_new", text: qsTr("Shut down"), run: () => sddm.powerOff() });
        return a;
    }

    Auth {
        id: authState

        user: root.userName
        userNeedsPassword: root.currentUser?.needsPassword ?? true
        sessionIndex: root.sessionIndex
        onStateChanged: {
            if (state === Auth.Succeeded)
                unlockAnim.start();
        }
    }

    Rectangle {
        anchors.fill: parent
        color: Colours.palette.m3surface
    }

    Image {
        id: background

        anchors.fill: parent
        source: root.cfg.BgSource ? Qt.resolvedUrl(root.cfg.BgSource) : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        sourceSize.width: root.width
        sourceSize.height: root.height
        opacity: 0
    }

    ColumnLayout {
        id: column

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: Math.round(root.height * 0.13)
        spacing: 0

        Clock {
            id: clock

            property real rise: Tokens.spacing.extraLarge

            Layout.alignment: Qt.AlignHCenter
            centerScale: root.scaleFactor * 0.45
            twelveHour: String(root.cfg.useTwelveHourClock ?? "") === "true"
            opacity: 0
            transform: Translate {
                y: clock.rise
            }
        }

        StyledText {
            id: date

            property date now: new Date()
            property real rise: Tokens.spacing.extraLarge

            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Math.round(Tokens.spacing.extraExtraLarge * root.scaleFactor)

            text: Qt.formatDate(now, "dddd • d MMM").toUpperCase()
            color: Colours.palette.m3onSurfaceVariant
            font.pointSize: Tokens.font.titleMedium * root.scaleFactor
            font.weight: Font.DemiBold
            font.letterSpacing: 1
            opacity: 0
            transform: Translate {
                y: date.rise
            }

            Timer {
                interval: 60000
                running: true
                repeat: true
                onTriggered: date.now = new Date()
            }
        }

        Loader {
            id: form

            property real rise: Tokens.spacing.extraLarge

            Layout.alignment: Qt.AlignHCenter
            Layout.topMargin: Math.round(110 * root.scaleFactor)
            active: root.primary
            opacity: 0
            transform: Translate {
                y: form.rise
            }

            sourceComponent: ColumnLayout {
                readonly property alias userField: userField

                // The password, unless there is no name yet to go with it.
                function focusInput(): void {
                    if (root.userName)
                        input.forceActiveFocus();
                    else
                        userField.focusInput();
                }

                width: root.formWidth
                spacing: Tokens.spacing.large

                UserField {
                    id: userField

                    Layout.fillWidth: true
                    scaleFactor: root.scaleFactor
                    text: root.userName
                    knownUser: root.currentUser?.name ?? ""
                    modelIcon: root.currentUser?.icon ?? ""
                    expandable: root.userItems.length > 0
                    expanded: userMenu.expanded
                    onEdited: name => root.userName = name
                    onAccepted: input.forceActiveFocus()
                    onMenuRequested: userMenu.open()
                }

                PasswordInput {
                    id: input

                    Layout.fillWidth: true
                    centerScale: root.scaleFactor
                    auth: authState
                }

                StateMessage {
                    Layout.fillWidth: true
                    auth: authState
                }
            }
        }
    }

    Loader {
        id: corner

        property real rise: Tokens.spacing.extraLarge

        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: Math.round(Tokens.padding.extraExtraLarge * 1.4 * root.scaleFactor)
        active: root.primary
        opacity: 0
        transform: Translate {
            y: corner.rise
        }

        sourceComponent: RowLayout {
            readonly property alias powerButton: powerButton
            readonly property alias sessionButton: sessionButton

            spacing: Math.round(Tokens.spacing.medium * root.scaleFactor)

            CornerButton {
                id: powerButton

                icon: "power_settings_new"
                scaleFactor: root.scaleFactor
                checked: powerMenu.expanded
                visible: root.powerActions.length > 0
                onClicked: powerMenu.open()
            }

            CornerButton {
                id: sessionButton

                icon: "settings"
                scaleFactor: root.scaleFactor
                checked: sessionMenu.expanded
                visible: root.sessionItems.length > 0
                onClicked: sessionMenu.open()
            }
        }
    }

    Menu {
        id: userMenu

        attachTo: form.item?.userField ?? form
        minWidth: root.formWidth
        items: root.userItems
        activeIndex: root.userIndex
        onSelected: index => {
            root.userName = users.objectAt(index)?.name ?? root.userName;
            form.item?.focusInput();
        }
    }

    Menu {
        id: powerMenu

        attachTo: corner.item?.powerButton ?? corner
        above: true
        items: root.powerActions
        onSelected: index => root.powerActions[index].run()
    }

    Menu {
        id: sessionMenu

        attachTo: corner.item?.sessionButton ?? corner
        above: true
        items: root.sessionItems
        activeIndex: root.sessionIndex
        onSelected: index => root.sessionIndex = index
    }

    // The password field keeps the keyboard, so whichever menu is open gets
    // these first.
    readonly property Menu openMenu: userMenu.expanded ? userMenu : powerMenu.expanded ? powerMenu : sessionMenu.expanded ? sessionMenu : null

    Shortcut {
        sequences: ["Up", "Backtab"]
        enabled: root.openMenu !== null
        onActivated: root.openMenu.move(-1)
    }
    Shortcut {
        sequences: ["Down", "Tab"]
        enabled: root.openMenu !== null
        onActivated: root.openMenu.move(1)
    }
    Shortcut {
        sequences: ["Return", "Enter", "Space"]
        enabled: root.openMenu !== null
        onActivated: root.openMenu.choose(root.openMenu.keyIndex)
    }
    Shortcut {
        sequence: "Escape"
        enabled: root.openMenu !== null
        onActivated: root.openMenu.expanded = false
    }

    // The wallpaper fades up from the surface colour, then the column arrives
    // from the top down, each part rising into place a beat after the last,
    // on the shell's emphasized curve.
    ParallelAnimation {
        id: initAnim

        running: true
        onFinished: form.item?.focusInput()

        Anim {
            target: background
            property: "opacity"
            to: 1
            type: Anim.StandardLarge
        }
        Reveal {
            target: clock
        }
        Reveal {
            target: date
            delay: 60
        }
        Reveal {
            target: form
            delay: 120
        }
        Reveal {
            target: corner
            delay: 180
        }
    }

    // On a successful login the column falls away and the wallpaper fades
    // back into the surface colour the session starts from.
    ParallelAnimation {
        id: unlockAnim

        Anim {
            targets: [clock, date, form, corner]
            property: "opacity"
            to: 0
            type: Anim.StandardSmall
        }
        Anim {
            target: column
            property: "scale"
            to: 0.9
            type: Anim.Standard
        }
        Anim {
            target: background
            property: "opacity"
            to: 0
            type: Anim.StandardLarge
        }
    }

    component Reveal: SequentialAnimation {
        id: reveal

        required property Item target
        property int delay

        PauseAnimation {
            duration: reveal.delay
        }
        ParallelAnimation {
            Anim {
                target: reveal.target
                property: "opacity"
                to: 1
                type: Anim.DefaultEffects
            }
            Anim {
                target: reveal.target
                property: "rise"
                to: 0
                type: Anim.Emphasized
            }
        }
    }
}
