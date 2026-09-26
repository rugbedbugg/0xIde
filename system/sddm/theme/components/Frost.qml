import QtQuick
import QtQuick.Effects

// The blur Hyprland puts behind every translucent Caelestia surface (the
// caelestia-drawers layer rule, on while appearance.transparency is), which a
// greeter has no compositor to do. The wallpaper under this item is blurred and
// cut to the surface's shape; the surface's tPalette colour goes on top.
//
// Hyprland's blur is dual Kawase at Caelestia's size 8 and 2 passes, which
// spreads much further than the desktop clock's in-QML blur (blurMax 64), then
// lifts saturation by its vibrancy (0.1696) and eases contrast (0.8916). The
// multiplier widens this blur to that reach, and the same two adjustments
// follow it.
//
// Fill the translucent surface with it, as its first child, naming the
// surface as frostedSurfaces does; it shows only while that surface is
// frosted.
Item {
    id: root

    required property string surface
    property real radius
    property real topLeftRadius: radius
    property real topRightRadius: radius
    property real bottomLeftRadius: radius
    property real bottomRightRadius: radius

    visible: Colours.frostedOn(surface) && Backdrop.source !== null

    layer.enabled: visible
    layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: mask
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1
    }

    MultiEffect {
        anchors.fill: parent
        autoPaddingEnabled: false
        blurEnabled: true
        blur: 1
        blurMax: 64
        blurMultiplier: 2
        saturation: 0.1696
        contrast: 0.8916 - 1

        source: ShaderEffectSource {
            sourceItem: Backdrop.source
            sourceRect: {
                Backdrop.track;
                root.width;
                root.height;
                if (!Backdrop.source || !root.visible)
                    return Qt.rect(0, 0, 0, 0);
                const p = root.mapToItem(Backdrop.source, 0, 0);
                return Qt.rect(p.x, p.y, root.width, root.height);
            }
        }
    }

    Rectangle {
        id: mask

        anchors.fill: parent
        topLeftRadius: root.topLeftRadius
        topRightRadius: root.topRightRadius
        bottomLeftRadius: root.bottomLeftRadius
        bottomRightRadius: root.bottomRightRadius
        visible: false
        layer.enabled: true
    }
}
