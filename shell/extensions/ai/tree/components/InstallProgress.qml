pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// An installer as its service reports it: the step it is on, a real fraction
// only while downloading, how it ended and why. It starts and stops nothing.
// The service gives installing, stage, outcome, bytes, total, stageSince,
// lastEvent, now, error, log, info.installed and stageLabel(), as AiRuntime and
// Speech do.
ColumnLayout {
    id: root

    required property var runtime
    // What it installs, for the headlines: "Local model", "Speech model".
    property string what
    // Said once it is installed, when there is something left to do.
    property string installedHint
    // A note for a step that takes long, by stage name.
    property var notes: ({})

    readonly property bool active: runtime.installing
    readonly property string outcome: active ? "" : runtime.outcome
    readonly property bool shown: active || !!outcome
    readonly property bool downloading: active && runtime.stage === "download" && runtime.total > 0
    // For a surface other than the default, such as a banner.
    property color textColour: Colours.palette.m3onSurface
    property color subtleColour: Colours.palette.m3outline
    property color accentColour: Colours.palette.m3primary
    readonly property int quiet: Math.max(0, Math.floor((runtime.now - runtime.lastEvent) / 1000))

    function clock(ms: real): string {
        const s = Math.max(0, Math.floor(ms / 1000));
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }
    function mib(bytes: real): int {
        return Math.round((bytes ?? 0) / 1048576);
    }

    visible: shown
    spacing: Tokens.spacing.extraSmall

    RowLayout {
        Layout.fillWidth: true
        spacing: Tokens.spacing.small

        MaterialIcon {
            text: root.outcome === "failed" ? "error" : root.outcome === "cancelled" ? "cancel" : root.outcome === "installed" ? "check_circle" : "downloading"
            color: root.outcome === "failed" ? Colours.palette.m3error : root.accentColour
        }
        StyledText {
            Layout.fillWidth: true
            wrapMode: Text.Wrap
            color: root.textColour
            font: Tokens.font.body.medium
            text: {
                if (root.outcome === "failed")
                    return qsTr("Installation failed");
                if (root.outcome === "cancelled")
                    return qsTr("Installation cancelled");
                if (root.outcome === "installed")
                    return qsTr("%1 installed").arg(root.what);
                return root.runtime.stageLabel(root.runtime.stage);
            }
        }
        // Time in this step, so a long one is seen to go on.
        StyledText {
            visible: root.active
            color: root.subtleColour
            font: Tokens.font.label.large
            text: root.clock(root.runtime.now - root.runtime.stageSince)
        }
    }

    // A real fraction only while downloading; every other step reports no
    // amount, so it moves without claiming one.
    StyledProgressBar {
        Layout.fillWidth: true
        visible: root.active
        indeterminate: !root.downloading
        value: root.downloading ? Math.min(1, root.runtime.bytes / root.runtime.total) : 0
    }

    StyledText {
        Layout.fillWidth: true
        visible: !!text
        wrapMode: Text.Wrap
        font: Tokens.font.label.large
        color: root.outcome === "failed" ? Colours.palette.m3error : root.subtleColour
        text: {
            const rt = root.runtime;
            if (root.outcome === "failed")
                return [rt.error, rt.stage ? qsTr("Step: %1").arg(rt.stageLabel(rt.stage)) : "", rt.log ? qsTr("Log: %1").arg(rt.log) : ""].filter(x => x).join("\n");
            if (root.outcome === "cancelled")
                return rt.info.installed ? "" : qsTr("Nothing was installed. Install starts over from the beginning.");
            if (root.outcome === "installed")
                return root.installedHint;
            if (root.downloading) {
                const got = qsTr("%1 of %2 MiB").arg(root.mib(rt.bytes)).arg(root.mib(rt.total));
                return root.quiet >= 15 ? qsTr("%1, no data for %2 s").arg(got).arg(root.quiet) : got;
            }
            return root.notes[rt.stage] ?? "";
        }
    }
}
