pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Caelestia.Config
import qs.components
import qs.components.controls
import qs.services

// The local model installer as AiRuntime reports it, so the area picker and
// Nexus show the same thing. It starts and stops nothing.
ColumnLayout {
    id: root

    readonly property bool active: AiRuntime.installing
    readonly property string outcome: active ? "" : AiRuntime.outcome
    readonly property bool shown: active || !!outcome
    readonly property bool downloading: active && AiRuntime.stage === "download" && AiRuntime.total > 0
    // For a surface other than the default, such as a banner.
    property color textColour: Colours.palette.m3onSurface
    property color subtleColour: Colours.palette.m3outline
    property color accentColour: Colours.palette.m3primary
    readonly property int quiet: Math.max(0, Math.floor((AiRuntime.now - AiRuntime.lastEvent) / 1000))

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
                    return qsTr("Local model installed");
                return AiRuntime.stageLabel(AiRuntime.stage);
            }
        }
        // Time in this step, so a build that takes minutes is seen to go on.
        StyledText {
            visible: root.active
            color: root.subtleColour
            font: Tokens.font.label.large
            text: root.clock(AiRuntime.now - AiRuntime.stageSince)
        }
    }

    // A real fraction only while downloading; every other step reports no
    // amount, so it moves without claiming one.
    StyledProgressBar {
        Layout.fillWidth: true
        visible: root.active
        indeterminate: !root.downloading
        value: root.downloading ? Math.min(1, AiRuntime.bytes / AiRuntime.total) : 0
    }

    StyledText {
        Layout.fillWidth: true
        visible: !!text
        wrapMode: Text.Wrap
        font: Tokens.font.label.large
        color: root.outcome === "failed" ? Colours.palette.m3error : root.subtleColour
        text: {
            if (root.outcome === "failed")
                return [AiRuntime.error, AiRuntime.stage ? qsTr("Step: %1").arg(AiRuntime.stageLabel(AiRuntime.stage)) : "", AiRuntime.log ? qsTr("Log: %1").arg(AiRuntime.log) : ""].filter(x => x).join("\n");
            if (root.outcome === "cancelled")
                return AiRuntime.info.installed ? "" : qsTr("Nothing was installed. Install starts over from the beginning.");
            if (root.outcome === "installed")
                return GlobalConfig.ai.backend === "managed" ? "" : qsTr("Choose Local as the backend to use it.");
            if (root.downloading) {
                const got = qsTr("%1 of %2 MiB").arg(root.mib(AiRuntime.bytes)).arg(root.mib(AiRuntime.total));
                return root.quiet >= 15 ? qsTr("%1, no data for %2 s").arg(got).arg(root.quiet) : got;
            }
            if (AiRuntime.stage === "build")
                return qsTr("Compiling takes several minutes. It carries on if you close this.");
            if (AiRuntime.stage === "waiting")
                return qsTr("Another installation or the running model holds the lock");
            return "";
        }
    }
}
