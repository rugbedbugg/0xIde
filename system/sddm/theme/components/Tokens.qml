pragma Singleton

import QtQuick

// Caelestia's design tokens, as the shell's Caelestia.Config plugin defines
// them (plugin/src/Caelestia/Config/tokens.hpp and appearanceconfig.hpp at the
// pinned revision). The plugin reads the user's shell.json and cannot run in
// the greeter, so the default values are carried here instead.
QtObject {
    id: root

    readonly property QtObject rounding: QtObject {
        readonly property int extraSmall: 4
        readonly property int small: 8
        readonly property int medium: 12
        readonly property int large: 16
        readonly property int largeIncreased: 20
        readonly property int extraLarge: 28
        readonly property int extraLargeIncreased: 32
        readonly property int extraExtraLarge: 48
        readonly property int full: 100000
    }

    readonly property QtObject spacing: QtObject {
        readonly property int extraSmall: 4
        readonly property int small: 8
        readonly property int medium: 12
        readonly property int large: 16
        readonly property int largeIncreased: 20
        readonly property int extraLarge: 28
        readonly property int extraLargeIncreased: 32
        readonly property int extraExtraLarge: 48
    }

    readonly property QtObject padding: QtObject {
        readonly property int extraSmall: 4
        readonly property int small: 8
        readonly property int medium: 12
        readonly property int large: 16
        readonly property int largeIncreased: 20
        readonly property int extraLarge: 28
        readonly property int extraLargeIncreased: 32
        readonly property int extraExtraLarge: 48
    }

    // Tokens.sizes.lock
    readonly property QtObject lock: QtObject {
        readonly property real heightMult: 0.7
        readonly property real ratio: 16 / 9
        readonly property int centerWidth: 600
    }

    // Google Sans Flex is not packaged; the installer copies the copy the
    // Caelestia dots placed in the user's font directory into fonts/. Rubik,
    // which Caelestia also uses, is packaged and stands in without it.
    readonly property FontLoader sansLoader: FontLoader {
        source: Qt.resolvedUrl("../fonts/GoogleSansFlex.ttf")
    }

    readonly property QtObject font: QtObject {
        readonly property string sans: root.sansLoader.status === FontLoader.Ready ? root.sansLoader.name : "Rubik"
        readonly property string mono: "CaskaydiaCove NF"
        readonly property string icon: "Material Symbols Rounded"
        readonly property string clock: sans

        // Point sizes, Tokens.font.<style>.<size>.pointSize
        readonly property int headlineLarge: 32
        readonly property int titleMedium: 16
        readonly property int bodyMedium: 14
        readonly property int bodySmall: 12
        readonly property int labelLarge: 14
        readonly property int monoSmall: 12

        // Tokens.font.icon: sizes are 48, 32, 24 and 20 px over 1.33
        readonly property int iconExtraLarge: 36
        readonly property int iconLarge: 24
        readonly property int iconMedium: 18
        readonly property int iconSmall: 15
    }

    readonly property QtObject anim: QtObject {
        readonly property QtObject durations: QtObject {
            readonly property int small: 200
            readonly property int normal: 400
            readonly property int large: 600
            readonly property int extraLarge: 1000
            readonly property int expressiveFastSpatial: 350
            readonly property int expressiveDefaultSpatial: 500
            readonly property int expressiveSlowSpatial: 650
            readonly property int expressiveFastEffects: 150
            readonly property int expressiveDefaultEffects: 200
            readonly property int expressiveSlowEffects: 300
        }

        // Cubic bezier splines, as QML's easing.bezierCurve takes them
        readonly property var emphasized: [0.05, 0, 2 / 15, 0.06, 1 / 6, 0.4, 5 / 24, 0.82, 0.25, 1, 1, 1]
        readonly property var standard: [0.2, 0, 0, 1, 1, 1]
        readonly property var standardAccel: [0.3, 0, 1, 1, 1, 1]
        readonly property var standardDecel: [0, 0, 0, 1, 1, 1]
        readonly property var expressiveFastSpatial: [0.42, 1.67, 0.21, 0.9, 1, 1]
        readonly property var expressiveDefaultSpatial: [0.38, 1.21, 0.22, 1, 1, 1]
        readonly property var expressiveSlowSpatial: [0.39, 1.29, 0.35, 0.98, 1, 1]
        readonly property var expressiveFastEffects: [0.31, 0.94, 0.34, 1, 1, 1]
        readonly property var expressiveDefaultEffects: [0.34, 0.8, 0.34, 1, 1, 1]
        readonly property var expressiveSlowEffects: [0.34, 0.88, 0.34, 1, 1, 1]
    }
}
