pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import "../components"

// modules/lock/Fetch.qml: the prompt chip, caelestiafetch.sh, the Caelestia
// logo, a few lines of system facts and the terminal colours. Before anyone
// has logged in, the facts worth showing are the machine's, not a session's.
StyledRect {
    id: root

    required property real rootHeight
    property string osName
    property string sessionName
    readonly property int cBoxSize: Tokens.font.bodyMedium * 2

    implicitHeight: layout.implicitHeight + Tokens.padding.extraLarge * 2
    radius: Tokens.rounding.medium
    color: Colours.palette.m3surfaceContainer

    ColumnLayout {
        id: layout

        anchors.fill: parent
        anchors.margins: Tokens.padding.extraLarge
        spacing: Tokens.spacing.small

        RowLayout {
            Layout.fillWidth: true
            spacing: Tokens.spacing.medium

            StyledRect {
                implicitWidth: prompt.implicitWidth + Tokens.padding.medium * 2
                implicitHeight: prompt.implicitHeight + Tokens.padding.small * 2
                color: Colours.palette.m3primary
                radius: Tokens.rounding.medium

                MonoText {
                    id: prompt

                    anchors.centerIn: parent
                    text: ">"
                    color: Colours.palette.m3onPrimary
                }
            }

            MonoText {
                Layout.fillWidth: true
                text: "caelestiafetch.sh"
                elide: Text.ElideRight
            }

            Logo {
                Layout.preferredHeight: prompt.implicitHeight + Tokens.padding.small * 2
                Layout.preferredWidth: Layout.preferredHeight * designWidth / designHeight
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: Tokens.padding.medium
            Layout.bottomMargin: Tokens.padding.medium
            spacing: Tokens.spacing.medium

            Repeater {
                model: {
                    const items = [];
                    if (root.osName)
                        items.push(`OS  : ${root.osName}`);
                    items.push(`HOST: ${sddm.hostName}`);
                    if (root.sessionName)
                        items.push(`WM  : ${root.sessionName}`);
                    return items;
                }

                MonoText {
                    required property string modelData

                    Layout.fillWidth: true
                    text: modelData
                    elide: Text.ElideRight
                }
            }
        }

        RowLayout {
            Layout.alignment: Qt.AlignHCenter
            visible: root.rootHeight > 500
            spacing: Tokens.spacing.largeIncreased

            Repeater {
                model: Math.max(0, Math.min(8, Math.floor((layout.width + Tokens.spacing.largeIncreased) / (root.cBoxSize + Tokens.spacing.largeIncreased))))

                StyledRect {
                    required property int index

                    implicitWidth: implicitHeight
                    implicitHeight: root.cBoxSize
                    color: Colours.palette[`m3term${index}`]
                    radius: Tokens.rounding.medium
                }
            }
        }
    }
}
