pragma Singleton

import QtQuick

// The Material 3 palette Caelestia generated, as system/sddm/sync writes it
// into theme.conf.user. Keys are the scheme's own names (primary,
// surfaceContainer, term0, ...) and read here as Colours.palette.m3<Name>, as
// the shell does. The defaults are Caelestia's default dark scheme, so the
// greeter still looks like Caelestia before the first sync.
QtObject {
    id: root

    readonly property var roles: ["primary", "onPrimary", "primaryContainer", "onPrimaryContainer", "secondary", "onSecondary", "secondaryContainer", "onSecondaryContainer", "tertiary", "onTertiary", "tertiaryContainer", "onTertiaryContainer", "error", "onError", "errorContainer", "onErrorContainer", "surface", "onSurface", "surfaceVariant", "onSurfaceVariant", "surfaceContainerLowest", "surfaceContainerLow", "surfaceContainer", "surfaceContainerHigh", "surfaceContainerHighest", "outline", "outlineVariant", "shadow", "scrim", "inverseSurface", "inverseOnSurface", "inversePrimary", "term0", "term1", "term2", "term3", "term4", "term5", "term6", "term7"]

    property bool light: false

    // Reads every role the theme configuration sets. Values that are missing
    // or not a colour keep the default rather than turning black.
    function load(config: var): void {
        if (!config)
            return;
        for (const role of roles) {
            const value = String(config[role] ?? "").trim();
            if (/^#?[0-9a-fA-F]{6}$/.test(value))
                palette["m3" + role] = value.startsWith("#") ? value : "#" + value;
        }
        light = String(config.mode ?? "") === "light";
    }

    readonly property QtObject palette: QtObject {
        property color m3primary: "#9bd0cc"
        property color m3onPrimary: "#0d4845"
        property color m3primaryContainer: "#255b58"
        property color m3onPrimaryContainer: "#b8ede9"
        property color m3secondary: "#b0ccc9"
        property color m3onSecondary: "#2c4543"
        property color m3secondaryContainer: "#27403e"
        property color m3onSecondaryContainer: "#a9c5c2"
        property color m3tertiary: "#d5efff"
        property color m3onTertiary: "#2e5c72"
        property color m3tertiaryContainer: "#b6e3fe"
        property color m3onTertiaryContainer: "#255369"
        property color m3error: "#fa746f"
        property color m3onError: "#490006"
        property color m3errorContainer: "#871f21"
        property color m3onErrorContainer: "#ff9993"
        property color m3surface: "#0a0f0f"
        property color m3onSurface: "#dce8e6"
        property color m3surfaceVariant: "#1d2827"
        property color m3onSurfaceVariant: "#a2adac"
        property color m3surfaceContainerLowest: "#000000"
        property color m3surfaceContainerLow: "#0e1514"
        property color m3surfaceContainer: "#131b1a"
        property color m3surfaceContainerHigh: "#192120"
        property color m3surfaceContainerHighest: "#1d2827"
        property color m3outline: "#6d7876"
        property color m3outlineVariant: "#3f4a49"
        property color m3shadow: "#000000"
        property color m3scrim: "#000000"
        property color m3inverseSurface: "#f6faf9"
        property color m3inverseOnSurface: "#515655"
        property color m3inversePrimary: "#336764"
        property color m3term0: "#343434"
        property color m3term1: "#769e00"
        property color m3term2: "#56e2c0"
        property color m3term3: "#81fcce"
        property color m3term4: "#76b6b3"
        property color m3term5: "#7aaee9"
        property color m3term6: "#83d8c9"
        property color m3term7: "#cddcd3"
    }
}
