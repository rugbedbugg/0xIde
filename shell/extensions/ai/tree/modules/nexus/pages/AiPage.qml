pragma ComponentBehavior: Bound

import QtQuick
import qs.modules.areapicker
import qs.modules.nexus.common

PageBase {
    title: qsTr("OCR & AI")

    AiSettings {
        width: parent.width
    }
}
