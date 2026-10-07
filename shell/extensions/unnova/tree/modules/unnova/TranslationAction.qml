pragma ComponentBehavior: Bound

import QtQuick
import qs.components.controls
import qs.services

// Shown only while a translation runs: there is nothing to cancel otherwise.
IconTextButton {
    id: root

    property var translator: Translator

    objectName: "translationCancel"
    visible: translator.translating
    icon: "close"
    text: qsTr("Cancel translation")
    type: IconTextButton.Tonal
    isRound: true
    onClicked: if (translator.translating) translator.cancel()
}
