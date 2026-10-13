pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common
import "power/sleepPolicy.js" as SleepPolicy

// Power settings, built from Nexus's own rows. For now one: how long the
// computer may be inactive before it sleeps. That is the sleep entry of
// general.idle.timeouts, which modules/IdleMonitors.qml already acts on, so
// activity resets it and Keep Awake, playing media and applications that
// inhibit idle all pause it as they always have. Locking, turning the display
// off and any other idle actions are left exactly as they are.
PageBase {
    id: root

    readonly property var policy: SleepPolicy.classify(GlobalConfig.general.idle.timeouts)
    // 0 when sleep is never automatic.
    readonly property int sleepSeconds: policy.seconds
    property bool customOpen

    readonly property list<MenuItem> sleepItems: [
        Preset {
            minutes: 5
        },
        Preset {
            minutes: 10
        },
        Preset {
            minutes: 15
        },
        Preset {
            minutes: 30
        },
        Preset {
            minutes: 60
        },
        Preset {
            minutes: 120
        },
        MenuItem {
            id: neverItem

            text: qsTr("Never")
            icon: "bedtime_off"
        },
        MenuItem {
            id: customItem

            text: qsTr("Custom…")
            activeText: root.describe(root.sleepSeconds)
            icon: "tune"
            activeIcon: "bedtime"
        }
    ]
    readonly property MenuItem activeItem: {
        if (sleepSeconds === 0)
            return neverItem;
        return sleepItems.find(i => (i.minutes ?? 0) * 60 === sleepSeconds) ?? customItem;
    }

    function describe(seconds: int): string {
        const h = Math.floor(seconds / 3600);
        const m = Math.floor(seconds % 3600 / 60);
        const s = seconds % 60;
        const parts = [];
        if (h)
            parts.push(qsTr("%1 h").arg(h));
        if (m)
            parts.push(qsTr("%1 min").arg(m));
        if (s || parts.length === 0)
            parts.push(qsTr("%1 s").arg(s));
        return parts.join(" ");
    }

    // Writes only a real change, so looking at the page or choosing what is
    // already set never puts the timeout list into shell.json.
    function write(list: var): void {
        if (list && !SleepPolicy.same(list, GlobalConfig.general.idle.timeouts))
            GlobalConfig.general.idle.timeouts = list;
    }

    function sleepAfter(minutes: int): void {
        write(SleepPolicy.withSleepAfter(GlobalConfig.general.idle.timeouts, minutes * 60));
    }

    function never(): void {
        write(SleepPolicy.withNever(GlobalConfig.general.idle.timeouts));
    }

    function openCustom(): void {
        picker.minutes = sleepSeconds > 0 ? Math.round(sleepSeconds / 300) * 5 : 10;
        picker.set(picker.minutes);
        customOpen = true;
    }

    title: qsTr("Power")

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        width: root.cappedWidth
        spacing: Tokens.spacing.extraSmall / 2

        SectionHeader {
            first: true
            text: qsTr("Sleep")
        }

        SelectRow {
            id: sleepRow

            visible: root.policy.state !== "multiple"
            first: true
            last: !root.customOpen
            label: qsTr("Sleep after inactivity")
            subtext: qsTr("Keep Awake and playing media pause this")
            menuItems: root.sleepItems
            active: root.activeItem
            onSelected: item => {
                if (item === customItem) {
                    root.openCustom();
                } else {
                    root.customOpen = false;
                    if (item === neverItem)
                        root.never();
                    else
                        root.sleepAfter(item.minutes);
                }
                // The menu sets the item it shows itself, after this; show the
                // configured one again, whatever changes it from now on.
                Qt.callLater(() => sleepRow.active = Qt.binding(() => root.activeItem));
            }
        }

        ConnectedRect {
            visible: root.customOpen && root.policy.state !== "multiple"
            last: true
            Layout.fillWidth: true
            implicitHeight: customLayout.implicitHeight + customLayout.anchors.margins * 2

            ColumnLayout {
                id: customLayout

                anchors.fill: parent
                anchors.margins: Tokens.padding.large
                spacing: Tokens.spacing.medium

                DurationPicker {
                    id: picker

                    Layout.alignment: Qt.AlignHCenter
                }

                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    color: Colours.palette.m3onSurfaceVariant
                    font: Tokens.font.body.small
                    text: picker.minutes === 0 ? qsTr("Choose how long it may be inactive") : qsTr("Sleeps after %1 without activity").arg(root.describe(picker.minutes * 60))
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: Tokens.spacing.small

                    TextButton {
                        type: TextButton.Text
                        text: qsTr("Cancel")
                        onClicked: root.customOpen = false
                    }

                    Item {
                        Layout.fillWidth: true
                    }

                    TextButton {
                        disabled: picker.minutes === 0
                        text: qsTr("Apply")
                        onClicked: {
                            root.sleepAfter(picker.minutes);
                            root.customOpen = false;
                        }
                    }
                }
            }
        }

        // Which entry is meant is not clear, so the page changes none of them.
        InfoRow {
            visible: root.policy.state === "multiple"
            first: true
            last: true
            icon: "warning"
            label: qsTr("Sleep after inactivity")
            subtext: qsTr("Set in shell.json, more than once")
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            Layout.leftMargin: Tokens.padding.small
            color: Colours.palette.m3outline
            font: Tokens.font.label.small
            wrapMode: Text.Wrap
            text: root.policy.state === "multiple" ? qsTr("More than one entry of general.idle.timeouts in shell.json suspends this computer, so which one this would change is not clear. Keep one of them and it can be set here. Locking and turning off the display keep their own timers.") : qsTr("Locking and turning off the display keep their own timers.")
        }
    }

    component Preset: MenuItem {
        property int minutes

        text: root.describe(minutes * 60)
        icon: "bedtime"
    }
}
