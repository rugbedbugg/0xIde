pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services
import qs.modules.nexus.common
import "power/sleepPolicy.js" as SleepPolicy
import "power/lidPolicy.js" as LidPolicy

// Power settings, built from Nexus's own rows. How long the computer may be
// inactive before it sleeps: the sleep entry of general.idle.timeouts, which
// modules/IdleMonitors.qml already acts on, so activity resets it and Keep
// Awake, playing media and applications that inhibit idle all pause it as they
// always have. Locking, turning the display off and any other idle actions are
// left exactly as they are.
//
// And what closing the lid does, undocked and with an external display. That
// is systemd-logind's to act on, so it holds while the shell is stopped or
// restarting: read through assets/power/logind_lid.py, and changed through the
// same file installed as root by system/lid, which writes one logind drop-in.
PageBase {
    id: root

    // Overridable only for the tests.
    property string lidScript: Qt.resolvedUrl("../../../assets/power/logind_lid.py").toString().replace("file://", "")
    property list<string> lidReader: ["/usr/bin/python3", "-I", lidScript, "status"]
    property list<string> lidWriter: ["sudo", "-n", "/usr/local/libexec/0xide-logind-lid"]
    // logind_lid.py's last answer; null until the first one.
    property var lid: null
    property string lidError
    property bool lidApplying
    readonly property string lidBlocked: LidPolicy.blocked(lid)

    function refreshLid(): void {
        lidStatus.running = true;
    }

    function setLid(which: string, action: string): void {
        if (lidBlocked || lidApplying)
            return;
        const want = LidPolicy.request(lid, which, action);
        if (want[0] === lid.undocked && want[1] === lid.docked && !LidPolicy.chargerDiffers(lid))
            return;
        lidError = "";
        lidApplying = true;
        lidApply.command = Array.from(lidWriter).concat(["set", want[0], want[1]]);
        lidApply.running = true;
    }

    function lidReason(): string {
        switch (lidBlocked) {
        case "reading":
            return qsTr("Reading the lid setting…");
        case "unreadable":
            return lid?.error ?? qsTr("logind did not answer");
        case "missing":
            return qsTr("Set by logind. Change it here after ./install --enable lid");
        case "outdated":
            return qsTr("The installed lid helper is older than the shell; run ./install --enable lid");
        case "rule":
            return qsTr("The lid helper is installed but its rule is not; run ./install --enable lid");
        case "overridden":
            return qsTr("%1 sets the lid after 0xIde, so a change here would not apply").arg(lid.overriddenBy.map(o => o.file).join(", "));
        }
        return "";
    }

    Component.onCompleted: Qt.callLater(refreshLid)

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

        SectionHeader {
            text: qsTr("Lid")
        }

        Repeater {
            model: [
                {
                    which: "undocked",
                    label: qsTr("When the lid is closed"),
                    subtext: qsTr("On battery and on a charger")
                },
                {
                    which: "docked",
                    label: qsTr("Closed with an external display"),
                    subtext: qsTr("Or when docked")
                }
            ]

            delegate: Item {
                id: lidRow

                required property var modelData
                required property int index

                Layout.fillWidth: true
                implicitHeight: lidRow.editable ? select.implicitHeight : info.implicitHeight

                readonly property bool editable: root.lidBlocked === "" && root.lid?.[modelData.which] !== undefined
                readonly property string value: root.lid?.[modelData.which] ?? ""
                // Hibernate only where logind can; an action set by something
                // other than this page is shown as it is, not offered.
                readonly property list<MenuItem> all: [
                    LidItem {
                        action: "suspend"
                    },
                    LidItem {
                        action: "ignore"
                    },
                    LidItem {
                        action: "lock"
                    },
                    LidItem {
                        action: "hibernate"
                    },
                    LidItem {
                        action: lidRow.value
                        elsewhere: true
                    }
                ]
                readonly property list<MenuItem> items: all.filter(i => i.elsewhere ? i.action !== "" && !LidPolicy.choosable(i.action, root.lid?.hibernate) : LidPolicy.choosable(i.action, root.lid?.hibernate))
                readonly property MenuItem current: items.find(i => i.action === value) ?? null

                SelectRow {
                    id: select

                    anchors.left: parent.left
                    anchors.right: parent.right
                    visible: lidRow.editable
                    enabled: !root.lidApplying
                    first: lidRow.index === 0
                    last: lidRow.index === 1
                    label: lidRow.modelData.label
                    subtext: lidRow.modelData.subtext
                    menuItems: lidRow.items
                    active: lidRow.current
                    onSelected: item => {
                        if (!item.elsewhere)
                            root.setLid(lidRow.modelData.which, item.action);
                        // The menu sets the item it shows itself, after this;
                        // show what logind does until it says otherwise.
                        Qt.callLater(() => select.active = Qt.binding(() => lidRow.current));
                    }
                }

                // Read only: what logind does, and why it cannot be changed here.
                InfoRow {
                    id: info

                    anchors.left: parent.left
                    anchors.right: parent.right
                    visible: !lidRow.editable
                    first: lidRow.index === 0
                    last: lidRow.index === 1
                    icon: root.lidBlocked === "overridden" || root.lidBlocked === "unreadable" ? "warning" : LidPolicy.icon(lidRow.value)
                    label: lidRow.modelData.label
                    value: lidRow.value ? LidPolicy.label(lidRow.value) : ""
                    subtext: lidRow.index === 0 ? root.lidReason() : lidRow.modelData.subtext
                }
            }
        }

        InfoRow {
            visible: root.lidError !== ""
            first: true
            last: true
            icon: "error"
            iconColour: Colours.palette.m3error
            label: qsTr("The lid setting was not changed")
            subtext: root.lidError
        }

        InfoRow {
            visible: (root.lid?.inhibitors ?? []).length > 0
            first: true
            last: true
            icon: "info"
            label: qsTr("Closing the lid is handled elsewhere for now")
            subtext: (root.lid?.inhibitors ?? []).map(i => `${i.who}: ${i.why}`).join("; ")
        }

        StyledText {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.spacing.small
            Layout.leftMargin: Tokens.padding.small
            color: Colours.palette.m3outline
            font: Tokens.font.label.small
            wrapMode: Text.Wrap
            text: (LidPolicy.chargerDiffers(root.lid) ? qsTr("On a charger the lid is set to %1 elsewhere; a change here sets both alike. ").arg(LidPolicy.label(root.lid.externalPower)) : "") + qsTr("systemd-logind acts on this, so it holds while the shell is stopped or restarting.")
        }
    }

    // PageBase takes one item as its content, so these are held, not children.
    readonly property Process lidStatus: Process {
        command: root.lidReader
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.lid = JSON.parse(text);
                } catch (e) {
                    root.lid = {
                        ok: false,
                        error: qsTr("The lid setting could not be read")
                    };
                }
            }
        }
    }

    readonly property Process lidApply: Process {
        stdout: StdioCollector {
            onStreamFinished: {
                let answer = null;
                try {
                    answer = JSON.parse(text);
                } catch (e) {}
                // Without an answer sudo refused before the helper ran.
                if (!answer?.ok)
                    root.lidError = answer?.error ?? (lidApplyErr.text.trim() || qsTr("The lid helper did not answer; run ./install --enable lid"));
                root.lidApplying = false;
                root.refreshLid();
            }
        }
        stderr: StdioCollector {
            id: lidApplyErr
        }
        onRunningChanged: {
            // A command that never started has no stream to finish.
            if (!running)
                Qt.callLater(() => {
                    if (root.lidApplying) {
                        root.lidApplying = false;
                        if (!root.lidError)
                            root.lidError = qsTr("The lid helper could not be run");
                        root.refreshLid();
                    }
                });
        }
    }

    component LidItem: MenuItem {
        property string action
        property bool elsewhere

        text: elsewhere ? qsTr("%1 (set elsewhere)").arg(LidPolicy.label(action)) : LidPolicy.label(action)
        icon: LidPolicy.icon(action)
    }

    component Preset: MenuItem {
        property int minutes

        text: root.describe(minutes * 60)
        icon: "bedtime"
    }
}
