pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQml.Models
import "components"
import "lock"

// The Caelestia lockscreen as an SDDM greeter (modules/lock/LockSurface.qml
// and Content.qml at the pinned shell revision).
//
// The same entrance: the lock tile spins in over the blurred wallpaper, then
// opens into the 16:9 panel as the symbol fades and the content grows in; and
// on a successful login, the same exit. The side columns hold what a greeter
// needs instead of what a lockscreen shows: the machine and the session to
// start on the left, the power actions and the accounts on the right.
//
// SDDM creates this once per screen. The panel is only on the primary one, so
// there is a single password field; the others show the wallpaper and tile.
Item {
    id: root

    readonly property bool primary: typeof primaryScreen === "undefined" || primaryScreen
    readonly property var cfg: typeof config === "undefined" ? ({}) : config
    readonly property alias unlocking: unlockAnim.running
    // For tests/run, which drives the login flow without a daemon.
    readonly property Auth auth: authState

    property int userIndex: Math.max(0, userModel.lastIndex)
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
        delegate: QtObject {
            required property string name
        }
    }

    property QtObject currentUser: null
    property string currentSession

    function refresh(): void {
        currentUser = users.objectAt(userIndex) ?? null;
        currentSession = sessions.objectAt(sessionIndex)?.name ?? "";
    }

    onUserIndexChanged: refresh()
    onSessionIndexChanged: refresh()

    Auth {
        id: authState

        user: root.currentUser?.name ?? userModel.lastUser
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

    Item {
        id: background

        anchors.fill: parent
        opacity: 0

        layer.enabled: true
        layer.effect: MultiEffect {
            autoPaddingEnabled: false
            blurEnabled: true
            blur: 1
            blurMax: 64
            blurMultiplier: 1
        }

        Image {
            anchors.fill: parent
            source: root.cfg.BgSource ? Qt.resolvedUrl(root.cfg.BgSource) : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            sourceSize.width: root.width
            sourceSize.height: root.height
        }
    }

    SequentialAnimation {
        id: unlockAnim

        ParallelAnimation {
            Anim {
                target: lockContent
                properties: "implicitWidth,implicitHeight"
                to: lockContent.size
            }
            Anim {
                target: lockBg
                property: "radius"
                to: lockContent.radius
            }
            Anim {
                target: content
                property: "scale"
                to: 0
            }
            Anim {
                target: content
                property: "opacity"
                to: 0
                type: Anim.StandardSmall
            }
            Anim {
                target: lockIcon
                property: "opacity"
                to: 1
                type: Anim.StandardLarge
            }
            Anim {
                target: background
                property: "opacity"
                to: 0
                type: Anim.StandardLarge
            }
            SequentialAnimation {
                PauseAnimation {
                    duration: Tokens.anim.durations.small
                }
                Anim {
                    type: Anim.Standard
                    target: lockContent
                    property: "opacity"
                    to: 0
                }
            }
        }
    }

    ParallelAnimation {
        id: initAnim

        running: true
        onFinished: {
            if (center.item)
                center.item.focusInput();
        }

        Anim {
            target: background
            property: "opacity"
            to: 1
            type: Anim.StandardLarge
        }
        SequentialAnimation {
            ParallelAnimation {
                Anim {
                    target: lockContent
                    property: "scale"
                    to: 1
                    type: Anim.FastSpatial
                }
                Anim {
                    target: lockContent
                    property: "rotation"
                    to: 360
                    duration: Tokens.anim.durations.expressiveFastSpatial
                    easing.bezierCurve: Tokens.anim.standardAccel
                }
            }
            // On a secondary screen the tile stays a tile: the same motion,
            // but to the sizes and opacity it already has.
            ParallelAnimation {
                Anim {
                    target: lockIcon
                    property: "rotation"
                    to: 360
                    easing.bezierCurve: Tokens.anim.standardDecel
                }
                Anim {
                    type: Anim.DefaultEffects
                    target: lockIcon
                    property: "opacity"
                    to: root.primary ? 0 : 1
                }
                Anim {
                    type: Anim.DefaultEffects
                    target: content
                    property: "opacity"
                    to: 1
                }
                Anim {
                    target: content
                    property: "scale"
                    to: 1
                }
                Anim {
                    target: lockBg
                    property: "radius"
                    to: root.primary ? Tokens.rounding.extraLarge * 1.5 : lockContent.radius
                }
                Anim {
                    target: lockContent
                    property: "implicitWidth"
                    to: root.primary ? lockContent.fullWidth : lockContent.size
                }
                Anim {
                    target: lockContent
                    property: "implicitHeight"
                    to: root.primary ? lockContent.fullHeight : lockContent.size
                }
            }
        }
    }

    Item {
        id: lockContent

        readonly property int size: lockIcon.implicitHeight + Tokens.padding.large * 4
        readonly property int radius: size / 4
        // Tokens.sizes.lock: 70% of the screen's height, at 16:9, but never
        // wider than the screen leaves room for.
        readonly property real fullHeight: root.height * Tokens.lock.heightMult
        readonly property real fullWidth: Math.min(fullHeight * Tokens.lock.ratio, root.width - Tokens.padding.extraExtraLarge * 2)

        anchors.centerIn: parent
        implicitWidth: size
        implicitHeight: size

        rotation: 180
        scale: 0

        StyledRect {
            id: lockBg

            anchors.fill: parent
            color: Colours.palette.m3surface
            radius: parent.radius

            layer.enabled: true
            layer.effect: MultiEffect {
                shadowEnabled: true
                blurMax: 15
                shadowColor: Qt.alpha(Colours.palette.m3shadow, 0.7)
            }
        }

        MaterialIcon {
            id: lockIcon

            anchors.centerIn: parent
            text: "lock"
            size: Tokens.font.iconExtraLarge * 4
            font.weight: Font.Bold
            rotation: 180
        }

        RowLayout {
            id: content

            anchors.centerIn: parent
            width: lockContent.fullWidth - Tokens.padding.extraLargeIncreased
            height: lockContent.fullHeight - Tokens.padding.extraLargeIncreased
            visible: root.primary

            opacity: 0
            scale: 0
            spacing: Tokens.spacing.largeIncreased * 2

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Tokens.spacing.medium

                FetchCard {
                    Layout.fillWidth: true
                    rootHeight: content.height
                    osName: root.cfg.osName ?? ""
                    sessionName: root.currentSession
                }

                SessionCard {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: root.sessionIndex
                    onSelected: index => root.sessionIndex = index
                }
            }

            Loader {
                id: center

                Layout.fillHeight: true
                Layout.preferredWidth: item?.Layout.preferredWidth ?? 0
                active: root.primary

                sourceComponent: Center {
                    auth: authState
                    screenHeight: root.height
                    realName: root.currentUser?.realName ?? ""
                    modelIcon: root.currentUser?.icon ?? ""
                    twelveHour: String(root.cfg.useTwelveHourClock ?? "") === "true"
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: Tokens.spacing.medium

                PowerCard {
                    Layout.fillWidth: true
                }

                UsersCard {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    currentIndex: root.userIndex
                    onSelected: index => {
                        root.userIndex = index;
                        center.item?.focusInput();
                    }
                }
            }
        }
    }
}
