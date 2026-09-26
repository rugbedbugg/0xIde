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
// Hyprland blurs the whole layer, drawing on what lies around each surface.
// So the blur here is taken over region and reach beyond it: the surface
// itself, or a group of alike surfaces (the corner buttons), which then all
// show the middle of the group's blur and so match, as buttons on one shell
// panel do.
//
// Fill the translucent surface with it, as its first child, naming the
// surface as frostedSurfaces does; it shows only while that surface is
// frosted.
Item {
    id: root

    required property string surface
    // The area blurred as one, which this surface lies within; itself when
    // unset.
    property Item region
    readonly property Item blurRegion: region ?? root
    // How far beyond region the blur draws: this blur's reach, blurMax 64
    // doubled by its multiplier.
    readonly property real reach: 128
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
        id: field

        // region and its reach, in the backdrop's coordinates and kept on
        // screen, where there is wallpaper to blur.
        readonly property rect area: {
            Backdrop.track;
            root.width;
            root.height;
            root.blurRegion.width;
            root.blurRegion.height;
            const src = Backdrop.source;
            if (!src || !root.visible)
                return Qt.rect(0, 0, 0, 0);
            const p = root.blurRegion.mapToItem(src, 0, 0);
            const x1 = Math.max(0, p.x - root.reach);
            const y1 = Math.max(0, p.y - root.reach);
            const x2 = Math.min(src.width, p.x + root.blurRegion.width + root.reach);
            const y2 = Math.min(src.height, p.y + root.blurRegion.height + root.reach);
            return Qt.rect(x1, y1, Math.max(0, x2 - x1), Math.max(0, y2 - y1));
        }
        // Where the blurred area sits in this surface: its own place for a
        // surface alone; for a group, the group's middle under this one's.
        readonly property point origin: {
            area;
            const src = Backdrop.source;
            if (!src)
                return Qt.point(0, 0);
            if (root.blurRegion === root)
                return src.mapToItem(root, area.x, area.y);
            const c = root.blurRegion.mapToItem(src, root.blurRegion.width / 2, root.blurRegion.height / 2);
            return Qt.point(area.x - c.x + root.width / 2, area.y - c.y + root.height / 2);
        }

        x: origin.x
        y: origin.y
        width: area.width
        height: area.height
        autoPaddingEnabled: false
        blurEnabled: true
        blur: 1
        blurMax: 64
        blurMultiplier: 2
        saturation: 0.1696
        contrast: 0.8916 - 1

        source: ShaderEffectSource {
            sourceItem: Backdrop.source
            sourceRect: field.area
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
