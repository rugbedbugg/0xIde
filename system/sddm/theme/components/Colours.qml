pragma Singleton

import QtQuick

// The Material 3 palette Caelestia generated, as system/sddm/sync writes it
// into theme.conf.user. Keys are the scheme's own names (primary,
// surfaceContainer, term0, ...) and read here as Colours.palette.m3<Name>, as
// the shell does. The defaults are Caelestia's default dark scheme, so the
// greeter still looks like Caelestia before the first sync.
//
// tPalette, transparency and wallLuminance are services/Colours.qml's: the
// user's appearance.transparency from shell.json, which sync writes beside the
// palette, and the wallpaper's mean luminance, which Main measures as the
// shell's ImageAnalyser does.
QtObject {
    id: root

    readonly property var roles: ["primary", "onPrimary", "primaryContainer", "onPrimaryContainer", "secondary", "onSecondary", "secondaryContainer", "onSecondaryContainer", "tertiary", "onTertiary", "tertiaryContainer", "onTertiaryContainer", "error", "onError", "errorContainer", "onErrorContainer", "surface", "onSurface", "surfaceVariant", "onSurfaceVariant", "surfaceContainerLowest", "surfaceContainerLow", "surfaceContainer", "surfaceContainerHigh", "surfaceContainerHighest", "outline", "outlineVariant", "shadow", "scrim", "inverseSurface", "inverseOnSurface", "inversePrimary", "term0", "term1", "term2", "term3", "term4", "term5", "term6", "term7"]

    property bool light: false
    property real wallLuminance

    // The plugin's defaults (appearanceconfig.hpp) until sync says otherwise.
    readonly property QtObject transparency: QtObject {
        property bool enabled: false
        property real configBase: 0.85
        property real configLayers: 0.4
        readonly property real base: Math.max(0, Math.min(1, configBase - (root.light ? 0.1 : 0)))
        readonly property real layers: Math.max(0, Math.min(1, configLayers))
    }

    function getLuminance(c: color): real {
        if (c.r == 0 && c.g == 0 && c.b == 0)
            return 0;
        return Math.sqrt(0.299 * (c.r ** 2) + 0.587 * (c.g ** 2) + 0.114 * (c.b ** 2));
    }

    function alterColour(c: color, a: real, layer: int): color {
        const luminance = getLuminance(c);

        const offset = (!light || layer == 1 ? 1 : -layer / 2) * (light ? 0.2 : 0.3) * (1 - transparency.base) * (1 + wallLuminance * (light ? (layer == 1 ? 3 : 1) : 2.5));
        const scale = (luminance + offset) / luminance;
        const r = Math.max(0, Math.min(1, c.r * scale));
        const g = Math.max(0, Math.min(1, c.g * scale));
        const b = Math.max(0, Math.min(1, c.b * scale));

        return Qt.rgba(r, g, b, a);
    }

    function layer(c: color, layer: var): color {
        if (!transparency.enabled)
            return c;

        return layer === 0 ? Qt.alpha(c, transparency.base) : alterColour(c, transparency.layers, layer ?? 1);
    }

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

        transparency.enabled = String(config.transparencyEnabled ?? "") === "true";
        const unit = v => {
            const n = parseFloat(String(v ?? ""));
            return isFinite(n) && n >= 0 && n <= 1 ? n : NaN;
        };
        if (!isNaN(unit(config.transparencyBase)))
            transparency.configBase = unit(config.transparencyBase);
        if (!isNaN(unit(config.transparencyLayers)))
            transparency.configLayers = unit(config.transparencyLayers);
    }

    // The surfaces the theme draws translucent, as the shell's M3TPalette has
    // them.
    readonly property QtObject tPalette: QtObject {
        readonly property color m3surface: root.layer(root.palette.m3surface, 0)
        readonly property color m3surfaceContainer: root.layer(root.palette.m3surfaceContainer)
        readonly property color m3surfaceContainerHigh: root.layer(root.palette.m3surfaceContainerHigh)
        readonly property color m3surfaceContainerHighest: root.layer(root.palette.m3surfaceContainerHighest)
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
