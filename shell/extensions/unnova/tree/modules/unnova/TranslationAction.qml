pragma ComponentBehavior: Bound

import QtQuick
import qs.components.controls
import qs.services

IconTextButton {
    id: root

    property var translator: Translator

    objectName: "translationCancel"
    icon: "close"
    text: qsTr("Cancel translation")
    type: IconTextButton.Tonal
    isRound: true
    disabled: !translator.translating
    onClicked: if (translator.translating) translator.cancel()
}
